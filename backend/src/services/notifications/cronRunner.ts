import { providerStatus } from "../../config/env.js";
import { runDailyBatch, runSundayBatch } from "./scheduledJobs.js";

/**
 * In-process notification cron.
 *
 * Why in-process and not a separate Railway service / pg_cron?
 *   - Zero extra infrastructure or cost — it rides inside the existing
 *     Fastify process.
 *   - The notification volume (a handful of daily scans) is trivial; it
 *     does not compete with request handling.
 *   - If Cooksy ever scales to multiple backend instances, the
 *     `dedup_key` unique constraint on `notification_dispatches` makes a
 *     double-run harmless — at worst two instances both scan and the
 *     second one's inserts collide and no-op.
 *
 * Cadence: the loop ticks every 30 minutes. On each tick it reads the
 * current Europe/Paris wall clock and fires a job if its slot is due and
 * hasn't already run today:
 *
 *   - Daily batch (dormant, lapsed, quota follow-up, cancellation save)
 *     → 11:00 Europe/Paris
 *   - Sunday batch (quota-reset anticipation + weekend meal-prep nudge)
 *     → Sunday 17:00 Europe/Paris
 *
 * `lastRun` keys jobs by their Paris date string so a job runs at most
 * once per calendar day even though the 30-minute tick lands in the
 * target hour twice.
 */

const TICK_INTERVAL_MS = 30 * 60 * 1000;

let started = false;
const lastRun = new Map<string, string>();

export function startNotificationCron(): void {
  if (started) return;
  started = true;

  // A first tick shortly after boot catches a job whose window we just
  // missed during a deploy (e.g. a deploy lands at 11:05).
  setTimeout(() => {
    void tick();
  }, 60 * 1000);

  const timer = setInterval(() => {
    void tick();
  }, TICK_INTERVAL_MS);
  // Don't keep the event loop alive purely for the cron.
  timer.unref();

  console.info("[cron] notification cron started (30-min tick)");
}

async function tick(): Promise<void> {
  try {
    if (!providerStatus.supabase) return;

    const now = new Date();
    const parisHour = parisHourOf(now);
    const parisWeekday = parisWeekdayOf(now); // "Sun" … "Sat"
    const parisDateKey = parisDateKeyOf(now); // "2026-05-19"

    // Daily batch at 11:00 Europe/Paris.
    if (parisHour === 11 && lastRun.get("daily") !== parisDateKey) {
      lastRun.set("daily", parisDateKey);
      console.info("[cron] running daily batch");
      const results = await runDailyBatch();
      console.info("[cron] daily batch done", JSON.stringify(results));
    }

    // Sunday batch (quota-reset anticipation + weekend meal-prep) —
    // Sunday 17:00 Europe/Paris.
    if (
      parisWeekday === "Sun" &&
      parisHour === 17 &&
      lastRun.get("sunday") !== parisDateKey
    ) {
      lastRun.set("sunday", parisDateKey);
      console.info("[cron] running Sunday batch");
      const results = await runSundayBatch();
      console.info("[cron] Sunday batch done", JSON.stringify(results));
    }
  } catch (err) {
    console.warn("[cron] tick failed:", (err as Error).message);
  }
}

// --- Europe/Paris wall-clock helpers ---------------------------------------

function parisHourOf(date: Date): number {
  const formatted = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Paris",
    hour: "numeric",
    hour12: false
  }).format(date);
  // Intl can return "24" for midnight in some runtimes — normalise.
  const hour = Number(formatted);
  return hour === 24 ? 0 : hour;
}

function parisWeekdayOf(date: Date): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Paris",
    weekday: "short"
  }).format(date);
}

function parisDateKeyOf(date: Date): string {
  // en-CA renders ISO-style YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris"
  }).format(date);
}
