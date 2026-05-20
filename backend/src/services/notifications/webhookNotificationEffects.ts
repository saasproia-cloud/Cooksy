import { getSupabaseServiceRoleClient } from "../../config/supabase.js";

import { sendPush } from "./pushService.js";
import { frenchLongDate } from "./frenchDate.js";

/**
 * Notification + subscription-state side effects driven by RevenueCat
 * webhook events.
 *
 * Called from the RC webhook handler AFTER `set_premium` and BEFORE the
 * 200 response. Everything here is best-effort: a failure must never
 * make the webhook return 5xx (that would have RC retry the whole
 * delivery and re-run `set_premium`). We swallow + log instead.
 *
 * Responsibilities:
 *   1. Keep `user_subscription_state` in sync (status, will_renew,
 *      current_period_end, trial/expiry/cancel anchors).
 *   2. Fire the *immediate* webhook-driven pushes:
 *        - D1 welcome_paid_d0          → first renewal after a trial
 *        - E3 cancelled_renewal_save   → CANCELLATION (auto-renew off)
 *      The *delayed* ones (E4 d-3, G1 lapsed d7) are handled by the
 *      daily cron scanning `user_subscription_state`.
 */

export interface RevenueCatEventLite {
  id: string;
  type: string;
  app_user_id: string;
  product_id?: string;
  period_type?: string;
  purchased_at_ms?: number;
  expiration_at_ms?: number;
}

export async function applyRevenueCatNotificationEffects(
  rcEvent: RevenueCatEventLite
): Promise<void> {
  try {
    const supabase = getSupabaseServiceRoleClient();
    const userId = rcEvent.app_user_id;
    const periodEnd = rcEvent.expiration_at_ms
      ? new Date(rcEvent.expiration_at_ms)
      : null;
    const isTrialPeriod = (rcEvent.period_type ?? "").toUpperCase() === "TRIAL";

    // Read prior state so we can detect "trial just converted".
    const { data: prior } = await supabase
      .from("user_subscription_state")
      .select("status, is_trial, trial_converted_at")
      .eq("user_id", userId)
      .maybeSingle();

    const now = new Date().toISOString();
    let nextState: Record<string, unknown> = {
      user_id: userId,
      last_event_type: rcEvent.type,
      updated_at: now
    };
    if (rcEvent.product_id) nextState.product_id = rcEvent.product_id;
    if (periodEnd) nextState.current_period_end = periodEnd.toISOString();

    switch (rcEvent.type) {
      case "INITIAL_PURCHASE": {
        nextState.status = isTrialPeriod ? "trial" : "active";
        nextState.is_trial = isTrialPeriod;
        nextState.will_renew = true;
        break;
      }

      case "RENEWAL": {
        // First renewal after a trial = the conversion moment.
        const wasTrial = prior?.is_trial === true;
        const alreadyConverted = Boolean(prior?.trial_converted_at);
        nextState.status = "active";
        nextState.is_trial = false;
        nextState.will_renew = true;
        if (wasTrial && !alreadyConverted) {
          nextState.trial_converted_at = now;
          // D1 — welcome the freshly-converted paying member. Utility
          // template (is_marketing=false) so it always lands.
          await safeSend(userId, "welcome_paid_d0", {});
        }
        break;
      }

      case "PRODUCT_CHANGE":
      case "UNCANCELLATION": {
        nextState.status = "active";
        nextState.will_renew = true;
        break;
      }

      case "CANCELLATION": {
        // The user turned off auto-renew. They keep access until
        // current_period_end. Fire the day-0 save immediately; the
        // day-(-3) save is queued by the daily cron.
        nextState.status = "cancelled";
        nextState.will_renew = false;
        nextState.cancelled_at = now;
        const expirationText = periodEnd ? frenchLongDate(periodEnd) : "bientôt";
        await safeSend(userId, "cancelled_renewal_save_d0", {
          expiration_date: expirationText
        });
        break;
      }

      case "EXPIRATION": {
        nextState.status = "expired";
        nextState.will_renew = false;
        nextState.expired_at = now;
        break;
      }

      case "SUBSCRIPTION_PAUSED": {
        nextState.status = "cancelled";
        nextState.will_renew = false;
        break;
      }

      default:
        // BILLING_ISSUE, TRANSFER, etc. — record the event type but
        // don't change the lifecycle status.
        break;
    }

    const { error } = await supabase
      .from("user_subscription_state")
      .upsert(nextState, { onConflict: "user_id" });
    if (error) {
      console.warn("[notif-effects] subscription_state upsert failed", error.message);
    }
  } catch (err) {
    console.warn(
      "[notif-effects] applyRevenueCatNotificationEffects failed",
      (err as Error).message
    );
  }
}

/** Fire a push, swallowing any error so the webhook still returns 200. */
async function safeSend(
  userId: string,
  templateId: string,
  variables: Record<string, string | number>
): Promise<void> {
  try {
    await sendPush({
      userId,
      templateId,
      variables,
      dedupBucket: "daily"
    });
  } catch (err) {
    console.warn(
      `[notif-effects] push ${templateId} failed for ${userId}:`,
      (err as Error).message
    );
  }
}
