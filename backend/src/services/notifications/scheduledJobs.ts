import { getSupabaseServiceRoleClient } from "../../config/supabase.js";

import { sendPush } from "./pushService.js";
import { daysUntilNextMonday } from "./frenchDate.js";

/**
 * Batch notification jobs run by the in-process cron (`cronRunner.ts`).
 *
 * Each job *scans* for users matching a time-based condition and calls
 * `sendPush` for each. The heavy lifting — quiet hours, frequency caps,
 * cooldowns, holdout, dedup — all lives in `sendPush` / `eligibilityChecker`,
 * so these functions stay simple "who, which template" enumerations.
 *
 * Idempotency: every template uses a `daily` dedup bucket, so even if a
 * job runs twice in a day (process restart, overlapping ticks) no user
 * is pushed twice. The cooldown_days on each template is the longer-term
 * backstop.
 *
 * Scale note (v1): each scan is capped at SCAN_LIMIT rows. For Cooksy's
 * current base that covers everyone; when the base grows past it, swap
 * the `.limit()` for keyset pagination.
 */

const SCAN_LIMIT = 5000;
/** How many pushes to fan out concurrently. APNs HTTP/2 multiplexes
 *  fine; the real limiter is the per-user eligibility DB reads. */
const SEND_CONCURRENCY = 5;

export interface JobResult {
  job: string;
  scanned: number;
  attempted: number;
}

// ---------------------------------------------------------------------------
// Daily batch — runs once a day at 11:00 Europe/Paris
// ---------------------------------------------------------------------------

export async function runDailyBatch(): Promise<JobResult[]> {
  const results: JobResult[] = [];
  for (const job of [
    runDormantScan,
    runLapsedScan,
    runQuotaFollowupScan,
    runCancellationSaveScan
  ]) {
    try {
      results.push(await job());
    } catch (err) {
      console.warn(`[cron] job ${job.name} failed:`, (err as Error).message);
      results.push({ job: job.name, scanned: 0, attempted: 0 });
    }
  }
  return results;
}

// ---------------------------------------------------------------------------
// F1 / F3 — dormant free users
// ---------------------------------------------------------------------------

/**
 * dormant_d7  → free users last active 7–8 days ago.
 * dormant_d30 → free users last active 30–31 days ago.
 *
 * The 24 h-wide band means the daily cron catches each user on exactly
 * one day as they cross it. profiles.last_active_at is bumped by the
 * `/api/events` `app.opened` beacon.
 */
async function runDormantScan(): Promise<JobResult> {
  const supabase = getSupabaseServiceRoleClient();
  let attempted = 0;
  let scanned = 0;

  for (const { template, lowDays, highDays } of [
    { template: "dormant_d7", lowDays: 8, highDays: 7 },
    { template: "dormant_d30", lowDays: 31, highDays: 30 }
  ]) {
    const low = new Date(Date.now() - lowDays * 86400 * 1000).toISOString();
    const high = new Date(Date.now() - highDays * 86400 * 1000).toISOString();

    const { data, error } = await supabase
      .from("profiles")
      .select("id")
      .eq("is_premium", false)
      .gte("last_active_at", low)
      .lt("last_active_at", high)
      .limit(SCAN_LIMIT);

    if (error) {
      console.warn(`[cron] dormant scan (${template}) query failed:`, error.message);
      continue;
    }
    const userIds = (data ?? []).map((r) => r.id as string);
    scanned += userIds.length;
    attempted += await dispatchBatch(userIds, template, () => ({}));
  }

  return { job: "dormant_scan", scanned, attempted };
}

// ---------------------------------------------------------------------------
// G1 — lapsed premium win-back (expired ~7 days ago)
// ---------------------------------------------------------------------------

async function runLapsedScan(): Promise<JobResult> {
  const supabase = getSupabaseServiceRoleClient();
  const low = new Date(Date.now() - 8 * 86400 * 1000).toISOString();
  const high = new Date(Date.now() - 7 * 86400 * 1000).toISOString();

  const { data, error } = await supabase
    .from("user_subscription_state")
    .select("user_id")
    .eq("status", "expired")
    .gte("expired_at", low)
    .lt("expired_at", high)
    .limit(SCAN_LIMIT);

  if (error) {
    console.warn("[cron] lapsed scan query failed:", error.message);
    return { job: "lapsed_scan", scanned: 0, attempted: 0 };
  }
  const userIds = (data ?? []).map((r) => r.user_id as string);
  const attempted = await dispatchBatch(userIds, "lapsed_d7_value", () => ({}));
  return { job: "lapsed_scan", scanned: userIds.length, attempted };
}

// ---------------------------------------------------------------------------
// B2 — quota reached ~1 day ago, still not premium
// ---------------------------------------------------------------------------

async function runQuotaFollowupScan(): Promise<JobResult> {
  const supabase = getSupabaseServiceRoleClient();
  const low = new Date(Date.now() - 2 * 86400 * 1000).toISOString();
  const high = new Date(Date.now() - 1 * 86400 * 1000).toISOString();

  const { data: events, error } = await supabase
    .from("notification_events")
    .select("user_id")
    .eq("event_type", "quota.reached")
    .gte("occurred_at", low)
    .lt("occurred_at", high)
    .limit(SCAN_LIMIT);

  if (error) {
    console.warn("[cron] quota followup query failed:", error.message);
    return { job: "quota_followup", scanned: 0, attempted: 0 };
  }

  // Dedupe user ids (a user could hit quota.reached several times).
  const candidateIds = Array.from(new Set((events ?? []).map((e) => e.user_id as string)));
  if (candidateIds.length === 0) {
    return { job: "quota_followup", scanned: 0, attempted: 0 };
  }

  // Drop anyone who converted to premium in the meantime.
  const { data: premiumRows } = await supabase
    .from("profiles")
    .select("id")
    .in("id", candidateIds)
    .eq("is_premium", true);
  const premiumSet = new Set((premiumRows ?? []).map((r) => r.id as string));
  const targetIds = candidateIds.filter((id) => !premiumSet.has(id));

  const daysUntilReset = daysUntilNextMonday();
  const attempted = await dispatchBatch(
    targetIds,
    "quota_reached_d1_followup",
    () => ({ days_until_reset: daysUntilReset })
  );
  return { job: "quota_followup", scanned: candidateIds.length, attempted };
}

// ---------------------------------------------------------------------------
// E4 — cancelled subscription, expiring in ~3 days
// ---------------------------------------------------------------------------

async function runCancellationSaveScan(): Promise<JobResult> {
  const supabase = getSupabaseServiceRoleClient();
  const low = new Date(Date.now() + 2.5 * 86400 * 1000).toISOString();
  const high = new Date(Date.now() + 3.5 * 86400 * 1000).toISOString();

  const { data, error } = await supabase
    .from("user_subscription_state")
    .select("user_id")
    .eq("will_renew", false)
    .in("status", ["cancelled", "active", "trial"])
    .gte("current_period_end", low)
    .lt("current_period_end", high)
    .limit(SCAN_LIMIT);

  if (error) {
    console.warn("[cron] cancellation-save query failed:", error.message);
    return { job: "cancellation_save", scanned: 0, attempted: 0 };
  }
  const userIds = (data ?? []).map((r) => r.user_id as string);
  const attempted = await dispatchBatch(
    userIds,
    "cancelled_renewal_save_d_minus_3",
    () => ({})
  );
  return { job: "cancellation_save", scanned: userIds.length, attempted };
}

// ---------------------------------------------------------------------------
// Sunday batch — B7 weekend meal-prep + B3 quota-reset anticipation
// ---------------------------------------------------------------------------

/**
 * Run both Sunday-evening jobs. They partition the free base cleanly:
 *   - quota-reset anticipation → free users who *hit* the cap this week
 *   - weekend meal-prep        → every *other* engaged free user
 * so nobody gets both pushes the same evening.
 */
export async function runSundayBatch(): Promise<JobResult[]> {
  const results: JobResult[] = [];
  // Compute the quota-hitter set once and share it between both jobs.
  let quotaHitterIds: Set<string>;
  try {
    quotaHitterIds = await recentQuotaHitterIds();
  } catch (err) {
    console.warn("[cron] recentQuotaHitterIds failed:", (err as Error).message);
    quotaHitterIds = new Set();
  }
  try {
    results.push(await runQuotaResetAnticipation(quotaHitterIds));
  } catch (err) {
    console.warn("[cron] quota_reset_anticipation failed:", (err as Error).message);
  }
  try {
    results.push(await runWeekendMealPrep(quotaHitterIds));
  } catch (err) {
    console.warn("[cron] weekend_meal_prep failed:", (err as Error).message);
  }
  return results;
}

/** Distinct user ids that raised a `quota.reached` event in the last 7 days. */
async function recentQuotaHitterIds(): Promise<Set<string>> {
  const supabase = getSupabaseServiceRoleClient();
  const since = new Date(Date.now() - 7 * 86400 * 1000).toISOString();
  const { data, error } = await supabase
    .from("notification_events")
    .select("user_id")
    .eq("event_type", "quota.reached")
    .gte("occurred_at", since)
    .limit(SCAN_LIMIT);
  if (error) throw new Error(error.message);
  return new Set((data ?? []).map((r) => r.user_id as string));
}

// B3 — quota reset anticipation (free users who hit the cap this week)
async function runQuotaResetAnticipation(
  quotaHitterIds: Set<string>
): Promise<JobResult> {
  const supabase = getSupabaseServiceRoleClient();
  const candidateIds = Array.from(quotaHitterIds);
  if (candidateIds.length === 0) {
    return { job: "quota_reset_anticipation", scanned: 0, attempted: 0 };
  }
  // Drop anyone who has since gone premium.
  const { data: premiumRows } = await supabase
    .from("profiles")
    .select("id")
    .in("id", candidateIds)
    .eq("is_premium", true);
  const premiumSet = new Set((premiumRows ?? []).map((r) => r.id as string));
  const targetIds = candidateIds.filter((id) => !premiumSet.has(id));
  const attempted = await dispatchBatch(
    targetIds,
    "quota_reset_anticipation",
    () => ({})
  );
  return {
    job: "quota_reset_anticipation",
    scanned: candidateIds.length,
    attempted
  };
}

// B7 — weekend meal-prep nudge (Sunday 17:00 Europe/Paris)
export async function runWeekendMealPrep(
  excludeIds: Set<string> = new Set()
): Promise<JobResult> {
  const supabase = getSupabaseServiceRoleClient();
  // Free users who opened the app within the last 14 days — engaged
  // enough that a meal-prep nudge is welcome, not spam.
  const activeSince = new Date(Date.now() - 14 * 86400 * 1000).toISOString();

  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .eq("is_premium", false)
    .gte("last_active_at", activeSince)
    .limit(SCAN_LIMIT);

  if (error) {
    console.warn("[cron] weekend meal-prep query failed:", error.message);
    return { job: "weekend_meal_prep", scanned: 0, attempted: 0 };
  }
  // Exclude this week's quota-hitters — they get quota_reset_anticipation
  // instead, so nobody is pushed twice on a Sunday evening.
  const userIds = (data ?? [])
    .map((r) => r.id as string)
    .filter((id) => !excludeIds.has(id));
  const attempted = await dispatchBatch(userIds, "weekend_meal_prep_free", () => ({}));
  return { job: "weekend_meal_prep", scanned: userIds.length, attempted };
}

// ---------------------------------------------------------------------------
// Shared dispatch helper
// ---------------------------------------------------------------------------

/**
 * Fan out `sendPush` to a list of users with bounded concurrency.
 * Returns the count of push attempts that didn't throw (skips count as
 * attempts — the eligibility funnel deciding "no" is a normal outcome).
 */
async function dispatchBatch(
  userIds: string[],
  templateId: string,
  variablesFor: (userId: string) => Record<string, string | number>
): Promise<number> {
  let attempted = 0;
  for (let i = 0; i < userIds.length; i += SEND_CONCURRENCY) {
    const chunk = userIds.slice(i, i + SEND_CONCURRENCY);
    await Promise.all(
      chunk.map(async (userId) => {
        try {
          await sendPush({
            userId,
            templateId,
            variables: variablesFor(userId),
            dedupBucket: "daily"
          });
          attempted += 1;
        } catch (err) {
          console.warn(
            `[cron] sendPush(${templateId}) failed for ${userId}:`,
            (err as Error).message
          );
        }
      })
    );
  }
  return attempted;
}
