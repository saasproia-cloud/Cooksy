import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";

import { env, providerStatus } from "../config/env.js";
import { getSupabaseServiceRoleClient } from "../config/supabase.js";
import { applyRevenueCatNotificationEffects } from "../services/notifications/webhookNotificationEffects.js";

/**
 * RevenueCat webhook handler.
 *
 * Trust model:
 *   - RevenueCat dashboard is configured with a shared secret. Every
 *     webhook call MUST carry `Authorization: Bearer <secret>` matching
 *     env.REVENUECAT_WEBHOOK_SECRET. Anything else → 401.
 *   - Each delivery has a unique `event.id`. We persist it to
 *     `webhook_events` so retries (RC retries on 5xx) are no-ops.
 *
 * Side effects:
 *   - On `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`, `UNCANCELLATION`
 *     we flip `profiles.is_premium = true`.
 *   - On `EXPIRATION`, `CANCELLATION` (after refund), `BILLING_ISSUE`
 *     we leave `is_premium = true` until expiration if it's just a
 *     cancellation (user keeps access until period end), but flip
 *     `false` on the `EXPIRATION` event when access actually ends.
 */

const revenueCatPayloadSchema = z.object({
  event: z.object({
    id: z.string(),
    type: z.string(),
    app_user_id: z.string(),
    original_app_user_id: z.string().optional(),
    product_id: z.string().optional(),
    period_type: z.string().optional(),
    purchased_at_ms: z.number().optional(),
    expiration_at_ms: z.number().optional(),
    environment: z.string().optional()
  })
}).passthrough();

const GRANT_ACCESS_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED"
]);

const REVOKE_ACCESS_EVENTS = new Set([
  "EXPIRATION",
  "SUBSCRIPTION_PAUSED",
  "REFUND"
]);

export async function registerRevenueCatWebhook(app: FastifyInstance): Promise<void> {
  app.post(
    "/api/webhooks/revenuecat",
    {
      // The webhook does not pass through the auth middleware — it's
      // not a user-authenticated route. The shared secret check below
      // is what gates it. Rate-limit is also disabled here: RevenueCat
      // bursts retries on 5xx and we want every one of those to reach
      // us so idempotency can dedupe them.
      config: {
        rateLimit: false
      }
    },
    async (request, reply) => handleWebhook(request, reply)
  );
}

async function handleWebhook(
  request: FastifyRequest,
  reply: FastifyReply
): Promise<unknown> {
  if (!providerStatus.revenueCatWebhook || !providerStatus.supabase) {
    request.log.error(
      { event: "webhook.misconfigured" },
      "RevenueCat webhook called but providers are not configured"
    );
    reply.status(503);
    return { error: "webhook_unavailable" };
  }

  // 1. Shared-secret auth. Constant-time compare to avoid timing leaks.
  const authHeader = request.headers.authorization;
  const expected = `Bearer ${env.REVENUECAT_WEBHOOK_SECRET}`;
  if (!authHeader || !timingSafeEqual(authHeader, expected)) {
    request.log.warn({ event: "webhook.unauthorized" }, "Bad RC webhook secret");
    reply.status(401);
    return { error: "unauthorized" };
  }

  // 2. Parse payload.
  const parseResult = revenueCatPayloadSchema.safeParse(request.body);
  if (!parseResult.success) {
    request.log.warn(
      { event: "webhook.bad_payload", issues: parseResult.error.flatten() },
      "RC webhook payload rejected"
    );
    reply.status(400);
    return { error: "bad_payload" };
  }
  const { event: rcEvent } = parseResult.data;

  const supabase = getSupabaseServiceRoleClient();

  // 3. Idempotency: have we already processed this event id?
  const { data: existing } = await supabase
    .from("webhook_events")
    .select("id")
    .eq("id", rcEvent.id)
    .maybeSingle();

  if (existing) {
    request.log.info(
      { event: "webhook.replay", id: rcEvent.id, type: rcEvent.type },
      "RC webhook replay ignored"
    );
    reply.status(200);
    return { ok: true, replay: true };
  }

  // 4. Apply the side effect, then persist the event row in the same
  //    flow. We persist the event AFTER applying so that a transient
  //    Supabase error on `set_premium` doesn't get masked by a
  //    successful idempotency insert.
  let granted: boolean | null = null;
  if (GRANT_ACCESS_EVENTS.has(rcEvent.type)) {
    granted = true;
  } else if (REVOKE_ACCESS_EVENTS.has(rcEvent.type)) {
    granted = false;
  }

  if (granted !== null) {
    const { error: rpcError } = await supabase.rpc("set_premium", {
      target_user_id: rcEvent.app_user_id,
      next_value: granted
    });
    if (rpcError) {
      request.log.error(
        { event: "webhook.set_premium_failed", id: rcEvent.id, message: rpcError.message },
        "Failed to update is_premium"
      );
      // Return 5xx so RC retries.
      reply.status(500);
      return { error: "set_premium_failed" };
    }
  }

  // 4b. Notification side effects — keep `user_subscription_state` in
  //     sync and fire the immediate webhook-driven pushes (welcome_paid,
  //     cancellation save). Best-effort: never blocks the 200 response,
  //     never makes RC retry. Runs only after the `set_premium` side
  //     effect succeeded so push copy can trust the premium flag.
  await applyRevenueCatNotificationEffects({
    id: rcEvent.id,
    type: rcEvent.type,
    app_user_id: rcEvent.app_user_id,
    product_id: rcEvent.product_id,
    period_type: rcEvent.period_type,
    purchased_at_ms: rcEvent.purchased_at_ms,
    expiration_at_ms: rcEvent.expiration_at_ms
  });

  // 5. Record the event so we never re-apply it.
  const { error: insertError } = await supabase
    .from("webhook_events")
    .insert({
      id: rcEvent.id,
      provider: "revenuecat",
      event_type: rcEvent.type,
      payload: request.body as Record<string, unknown>
    });

  if (insertError) {
    // The side effect already landed. If RC retries the delivery, the
    // event id check above will still no-op us (granted state is the
    // same), so a duplicate insert error here would be the path. Log
    // but treat as success.
    request.log.warn(
      {
        event: "webhook.idempotency_insert_failed",
        id: rcEvent.id,
        message: insertError.message
      },
      "RC webhook idempotency row not persisted"
    );
  }

  request.log.info(
    {
      event: "webhook.applied",
      id: rcEvent.id,
      type: rcEvent.type,
      granted
    },
    "RC webhook applied"
  );
  reply.status(200);
  return { ok: true };
}

/**
 * Length-stable equality check. Avoids the trivial timing leak of
 * `===`, but does not pull in `node:crypto` for a tiny dependency.
 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
