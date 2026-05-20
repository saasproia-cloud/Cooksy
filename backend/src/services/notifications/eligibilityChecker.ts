import { getSupabaseServiceRoleClient } from "../../config/supabase.js";
import type {
  NotificationTemplate,
  SkipReason
} from "./types.js";

/**
 * Eligibility checks the dispatcher runs *before* talking to APNs.
 *
 * The point isn't just compliance with the anti-spam rules in the plan,
 * it's also to make every "we sent X" line in the dashboard meaningful:
 * a high `skipped:cooldown` count tells us the cron is firing too often;
 * a high `skipped:muted_marketing` tells us we're losing reach.
 */

export interface EligibilityContext {
  userId: string;
  template: NotificationTemplate;
  now: Date;
}

export interface EligibilityResult {
  allowed: boolean;
  reason?: SkipReason;
}

/** Europe/Paris quiet hours: 22:00–08:00 inclusive at 22, exclusive at 08. */
const QUIET_START_HOUR = 22;
const QUIET_END_HOUR = 8;

/**
 * Returns whether `now` falls in the Cooksy quiet window for the user's
 * timezone (defaults to Europe/Paris). Utility (P0/P1 non-marketing)
 * notifications can bypass this — that's the caller's call.
 */
export function isInQuietHours(now: Date, timezone = "Europe/Paris"): boolean {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour: "numeric",
    hour12: false
  });
  // formatter.format returns e.g. "23" or "00"
  const hour = Number(formatter.format(now));
  if (Number.isNaN(hour)) return false;
  return hour >= QUIET_START_HOUR || hour < QUIET_END_HOUR;
}

const DAILY_PUSH_CAP = 2;     // P2/P3 combined per day
const WEEKLY_PUSH_CAP = 4;    // toutes catégories
const ABSOLUTE_DAILY_CAP = 3; // even with urgent P0/P1 stacked

/**
 * Run the full eligibility funnel for one (user, template) pair.
 * Returns `{ allowed: false, reason }` if any check fails; the caller
 * passes `reason` straight into the dispatches row.
 */
export async function checkEligibility(
  ctx: EligibilityContext
): Promise<EligibilityResult> {
  const { userId, template, now } = ctx;
  const supabase = getSupabaseServiceRoleClient();

  if (!template.is_active) {
    return { allowed: false, reason: "template_inactive" };
  }

  // ---- 1. Per-user preferences ---------------------------------------------
  // We honor opt-outs only for marketing templates. Utilities (trial
  // reminders, cancellation saves, welcome paid) are transactional and
  // bypass all of this.
  if (template.is_marketing) {
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select(
        "marketing_enabled, promo_enabled, suggestion_enabled, reminder_enabled, digest_enabled, category_overrides"
      )
      .eq("user_id", userId)
      .maybeSingle();

    if (prefs) {
      if (prefs.marketing_enabled === false) {
        return { allowed: false, reason: "muted_marketing" };
      }

      const overrides = (prefs.category_overrides ?? {}) as Record<string, boolean>;
      if (overrides[template.category] === false) {
        return { allowed: false, reason: "muted_category" };
      }

      // Map categories to the boolean toggles surfaced in the iOS UI.
      const categoryGate = mapCategoryToToggle(template.category, prefs);
      if (categoryGate === false) {
        return { allowed: false, reason: "muted_category" };
      }
    }
  }

  // ---- 2. Holdout -----------------------------------------------------------
  // Marketing pushes only — utilities still reach holdouts so the
  // experience doesn't break (no trial reminder = chargeback risk).
  if (template.is_marketing) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("holdout_group")
      .eq("id", userId)
      .maybeSingle();
    if (profile?.holdout_group === true) {
      return { allowed: false, reason: "holdout" };
    }
  }

  // ---- 3. Per-template cooldown --------------------------------------------
  if (template.cooldown_days > 0) {
    const cutoff = new Date(now.getTime() - template.cooldown_days * 86400 * 1000);
    const { data: lastSend } = await supabase
      .from("notification_dispatches")
      .select("sent_at")
      .eq("user_id", userId)
      .eq("template_id", template.id)
      .not("sent_at", "is", null)
      .gte("sent_at", cutoff.toISOString())
      .order("sent_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (lastSend?.sent_at) {
      return { allowed: false, reason: "cooldown" };
    }
  }

  // ---- 4. Frequency caps (daily + weekly) ----------------------------------
  // We count *sent* rows in the window. Skipped/failed don't count
  // against the cap — only what actually pinged the user.
  const dayStart = new Date(now.getTime() - 24 * 3600 * 1000);
  const weekStart = new Date(now.getTime() - 7 * 86400 * 1000);

  const [{ count: dailyCount }, { count: weeklyCount }] = await Promise.all([
    supabase
      .from("notification_dispatches")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("sent_at", dayStart.toISOString())
      .not("sent_at", "is", null),
    supabase
      .from("notification_dispatches")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("sent_at", weekStart.toISOString())
      .not("sent_at", "is", null)
  ]);

  // P0/P1 urgent (trial ending, quota hit) get one extra slot to land
  // even when the day is already full, up to the absolute ceiling.
  const dailyCap =
    template.priority <= 1 ? ABSOLUTE_DAILY_CAP : DAILY_PUSH_CAP;

  if ((dailyCount ?? 0) >= dailyCap) {
    return { allowed: false, reason: "quota_exceeded_daily" };
  }
  if ((weeklyCount ?? 0) >= WEEKLY_PUSH_CAP) {
    return { allowed: false, reason: "quota_exceeded_weekly" };
  }

  // ---- 5. App-in-foreground guard ------------------------------------------
  // If the user opened the app within the last 2 hours we suppress
  // dormant/quota/suggestion pushes — they're already with us. Utilities
  // (trial reminders, cancellation saves) are unaffected.
  if (template.is_marketing) {
    const recentOpenCutoff = new Date(now.getTime() - 2 * 3600 * 1000);
    const { data: lastOpen } = await supabase
      .from("notification_events")
      .select("occurred_at")
      .eq("user_id", userId)
      .eq("event_type", "app.opened")
      .gte("occurred_at", recentOpenCutoff.toISOString())
      .order("occurred_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (lastOpen?.occurred_at && shouldSuppressWhenRecentlyOpen(template)) {
      return { allowed: false, reason: "user_in_app" };
    }
  }

  return { allowed: true };
}

/**
 * Some marketing pushes still make sense when the user just used the
 * app (e.g. gift_expires_6h — they should be reminded even mid-session).
 * Whitelist categories where in-app suppression is the wrong call.
 */
function shouldSuppressWhenRecentlyOpen(template: NotificationTemplate): boolean {
  return template.category !== "gift" && template.category !== "trial";
}

function mapCategoryToToggle(
  category: NotificationTemplate["category"],
  prefs: {
    promo_enabled: boolean;
    suggestion_enabled: boolean;
    reminder_enabled: boolean;
    digest_enabled: boolean;
  }
): boolean | undefined {
  switch (category) {
    case "quota":
    case "lapsed":
    case "gift":
      return prefs.promo_enabled;
    case "dormant":
    case "milestone":
      return prefs.suggestion_enabled;
    case "trial":
    case "premium":
    case "onboarding":
      return prefs.reminder_enabled;
    default:
      return undefined;
  }
}
