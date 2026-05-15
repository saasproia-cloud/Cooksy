import { getSupabaseServiceRoleClient } from "../config/supabase.js";

/**
 * Server-side source of truth for premium status and import quota.
 *
 * The iOS client's ImportQuotaService is now strictly an UX hint — the
 * backend enforces the real limit. A free user that bypasses the
 * client-side counter will still hit 402 here once they exceed the
 * weekly cap.
 */

const FREE_IMPORTS_PER_WEEK = 5;
const PREMIUM_IMPORTS_PER_WEEK = 100;

export type EntitlementSnapshot = {
  isPremium: boolean;
  weeklyLimit: number;
  importsUsed: number;
  remaining: number;
};

export class QuotaExceededError extends Error {
  constructor(public readonly snapshot: EntitlementSnapshot) {
    super("Import quota exceeded.");
    this.name = "QuotaExceededError";
  }
}

/**
 * Lookup the user's premium status. Never trust a client claim — we
 * read straight from `profiles.is_premium`, which only the RevenueCat
 * webhook is allowed to write.
 */
export async function getIsPremium(userId: string): Promise<boolean> {
  const supabase = getSupabaseServiceRoleClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("is_premium")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to read premium status: ${error.message}`);
  }
  return Boolean(data?.is_premium);
}

/**
 * Atomically consume one import slot for the current ISO week. Throws
 * {@link QuotaExceededError} if the user has already hit their limit.
 *
 * The post-increment trick keeps the check-and-set race-free: the
 * Postgres function runs `INSERT … ON CONFLICT UPDATE … RETURNING` in a
 * single statement, so two concurrent imports cannot both squeeze
 * through at the boundary.
 */
export async function consumeImportSlot(
  userId: string
): Promise<EntitlementSnapshot> {
  const supabase = getSupabaseServiceRoleClient();
  const isPremium = await getIsPremium(userId);
  const weeklyLimit = isPremium ? PREMIUM_IMPORTS_PER_WEEK : FREE_IMPORTS_PER_WEEK;
  const windowStart = currentIsoWeekStart();

  const { data, error } = await supabase.rpc("consume_import_quota", {
    target_user_id: userId,
    current_window_start: windowStart
  });

  if (error) {
    throw new Error(`Failed to consume import slot: ${error.message}`);
  }

  // The RPC returns a SETOF row — Supabase materializes it as an array.
  const row = Array.isArray(data) ? data[0] : data;
  const importsUsed = typeof row?.imports_used === "number" ? row.imports_used : 0;
  const snapshot: EntitlementSnapshot = {
    isPremium,
    weeklyLimit,
    importsUsed,
    remaining: Math.max(0, weeklyLimit - importsUsed)
  };

  if (importsUsed > weeklyLimit) {
    // We've already incremented the counter past the cap. That's fine
    // — the window resets every Monday, so the over-shoot is bounded
    // to this week. Surfacing 402 immediately is what matters.
    throw new QuotaExceededError({
      ...snapshot,
      importsUsed: weeklyLimit,
      remaining: 0
    });
  }

  return snapshot;
}

/**
 * Read-only view of the user's current usage. Used by the iOS app for
 * UX (badge counter) — does not consume a slot.
 */
export async function readEntitlement(userId: string): Promise<EntitlementSnapshot> {
  const supabase = getSupabaseServiceRoleClient();
  const isPremium = await getIsPremium(userId);
  const weeklyLimit = isPremium ? PREMIUM_IMPORTS_PER_WEEK : FREE_IMPORTS_PER_WEEK;
  const windowStart = currentIsoWeekStart();

  const { data, error } = await supabase
    .from("import_quota_window")
    .select("imports_used")
    .eq("user_id", userId)
    .eq("window_start_date", windowStart)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to read quota window: ${error.message}`);
  }

  const importsUsed = data?.imports_used ?? 0;
  return {
    isPremium,
    weeklyLimit,
    importsUsed,
    remaining: Math.max(0, weeklyLimit - importsUsed)
  };
}

/**
 * ISO-week start date (Monday) in UTC, as a YYYY-MM-DD string. Postgres
 * parses this directly into a `date` column.
 */
function currentIsoWeekStart(now: Date = new Date()): string {
  const utc = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  // getUTCDay returns 0..6 with 0 = Sunday. Convert to ISO (Monday = 0).
  const dayOfWeek = (utc.getUTCDay() + 6) % 7;
  utc.setUTCDate(utc.getUTCDate() - dayOfWeek);
  return utc.toISOString().slice(0, 10);
}
