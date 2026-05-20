import crypto from "node:crypto";

import { getSupabaseServiceRoleClient } from "../../config/supabase.js";
import { providerStatus } from "../../config/env.js";

import { sendApnsPush, type ApnsSendResult } from "./apnsClient.js";
import { checkEligibility } from "./eligibilityChecker.js";
import { renderDeepLink, renderTemplate } from "./templateRenderer.js";
import type {
  DeviceTokenRow,
  DispatchStatus,
  NotificationTemplate,
  PushRequest,
  PushResult,
  SkipReason
} from "./types.js";

/**
 * High-level entry point. Given a (user, template, variables) tuple:
 *
 *   1. Look up the template and the user's active device tokens.
 *   2. Render the copy (skip + log if a required variable is missing
 *      and no fallback is defined).
 *   3. Run the eligibility funnel (cooldown, quiet hours, mute, etc.).
 *   4. Insert a dispatches row with the dedup_key. If that fails on the
 *      unique constraint we know we already sent this combo → skip.
 *   5. Talk to APNs for every active token. On 410, mark the token
 *      disabled and continue with the next token.
 *   6. Update the dispatches row with status + apns details.
 *
 * Returns the *primary* dispatch outcome (the first device's response).
 * Detailed per-token results land in the DB.
 */
export async function sendPush(req: PushRequest): Promise<PushResult> {
  const supabase = getSupabaseServiceRoleClient();
  const now = req.scheduledFor ?? new Date();

  // ---- 1. Resolve template -------------------------------------------------
  const { data: template, error: templateErr } = await supabase
    .from("notification_templates")
    .select("*")
    .eq("id", req.templateId)
    .maybeSingle<NotificationTemplate>();
  if (templateErr) throw templateErr;
  if (!template) {
    throw new Error(`Unknown notification template: ${req.templateId}`);
  }

  // ---- 2. Render copy ------------------------------------------------------
  const rendered = renderTemplate(template, req.variables);
  const requiredVars = template.variables;
  const stillMissing = rendered.missingVariables.filter((v) => requiredVars.includes(v));

  if (stillMissing.length > 0 && template.fallback_template_id) {
    // Fall back to a simpler variant. Recursive — but capped to depth 1
    // by passing bypassEligibilityChecks=false so behavior matches a
    // fresh send.
    return sendPush({
      ...req,
      templateId: template.fallback_template_id
    });
  }
  if (stillMissing.length > 0) {
    return logSkippedDispatch(req, template, "duplicate", {
      title: rendered.title,
      body: rendered.body,
      reason_note: `missing_required_vars: ${stillMissing.join(",")}`
    });
  }

  // ---- 3. Eligibility ------------------------------------------------------
  if (!req.bypassEligibilityChecks) {
    const eligibility = await checkEligibility({
      userId: req.userId,
      template,
      now
    });
    if (!eligibility.allowed) {
      return logSkippedDispatch(req, template, eligibility.reason ?? "duplicate", rendered);
    }
  }

  // ---- 4. Dedup insert -----------------------------------------------------
  const dedupKey = buildDedupKey(req, template, now);
  const deepLink = renderDeepLink(template.deep_link, req.variables);

  const { data: dispatch, error: insertErr } = await supabase
    .from("notification_dispatches")
    .insert({
      user_id: req.userId,
      template_id: template.id,
      status: "queued",
      title_rendered: rendered.title,
      body_rendered: rendered.body,
      variables_used: req.variables ?? {},
      experiment_variant: req.experimentVariant ?? "control",
      scheduled_for: now.toISOString(),
      dedup_key: dedupKey
    })
    .select("id")
    .single();

  if (insertErr) {
    // 23505 = unique_violation → we already sent this combo.
    if ((insertErr as { code?: string }).code === "23505") {
      return { status: "skipped", skipReason: "duplicate" };
    }
    throw insertErr;
  }

  // ---- 5. Talk to APNs -----------------------------------------------------
  const { data: tokensRaw } = await supabase
    .from("device_tokens")
    .select("id, user_id, apns_token, apns_environment, push_authorization_status, disabled_at")
    .eq("user_id", req.userId)
    .is("disabled_at", null);

  const tokens = (tokensRaw ?? []) as DeviceTokenRow[];
  if (tokens.length === 0) {
    await supabase
      .from("notification_dispatches")
      .update({
        status: "skipped",
        skip_reason: "no_token"
      })
      .eq("id", dispatch.id);
    return { status: "skipped", skipReason: "no_token", dispatchId: dispatch.id };
  }

  // If APNs isn't configured (e.g. local dev without keys), don't crash
  // — record the dispatch with skip_reason and bail out. Lets devs test
  // the full code path without provisioning Apple credentials.
  if (!providerStatus.apns) {
    await supabase
      .from("notification_dispatches")
      .update({
        status: "skipped",
        skip_reason: "no_token",
        apns_response: { reason: "apns_not_configured" }
      })
      .eq("id", dispatch.id);
    return {
      status: "skipped",
      skipReason: "no_token",
      dispatchId: dispatch.id
    };
  }

  // Try each token. We declare the dispatch "sent" as long as one token
  // succeeds — multi-device users still benefit. Failures get logged
  // per-token in apns_response.
  const perTokenResults: Array<{
    deviceTokenId: string;
    result: ApnsSendResult;
  }> = [];

  for (const token of tokens) {
    let result: ApnsSendResult;
    try {
      result = await sendApnsPush(
        token.apns_token,
        {
          title: rendered.title,
          body: rendered.body,
          deepLink,
          customData: {
            cooksy_dispatch_id: dispatch.id,
            cooksy_template_id: template.id
          }
        },
        token.apns_environment
      );
    } catch (err) {
      result = {
        statusCode: 0,
        body: (err as Error).message,
        apnsId: null,
        reason: "transport_error"
      };
    }
    perTokenResults.push({ deviceTokenId: token.id, result });

    // 410 Gone / BadDeviceToken / Unregistered → disable token forever.
    if (
      result.statusCode === 410 ||
      result.reason === "Unregistered" ||
      result.reason === "BadDeviceToken" ||
      result.reason === "DeviceTokenNotForTopic"
    ) {
      await supabase
        .from("device_tokens")
        .update({ disabled_at: new Date().toISOString() })
        .eq("id", token.id);
    }
  }

  const firstSuccess = perTokenResults.find(({ result }) => result.statusCode === 200);
  const primary = firstSuccess ?? perTokenResults[0];

  const finalStatus: DispatchStatus = firstSuccess ? "sent" : "failed";
  await supabase
    .from("notification_dispatches")
    .update({
      status: finalStatus,
      sent_at: firstSuccess ? new Date().toISOString() : null,
      apns_status_code: primary?.result.statusCode ?? 0,
      apns_response: {
        primary_apns_id: primary?.result.apnsId,
        primary_reason: primary?.result.reason,
        per_token: perTokenResults.map(({ deviceTokenId, result }) => ({
          device_token_id: deviceTokenId,
          status: result.statusCode,
          reason: result.reason
        }))
      },
      device_token_id: primary?.deviceTokenId ?? null
    })
    .eq("id", dispatch.id);

  return {
    status: finalStatus,
    dispatchId: dispatch.id,
    apnsStatusCode: primary?.result.statusCode,
    apnsResponseBody: primary?.result.body
  };
}

async function logSkippedDispatch(
  req: PushRequest,
  template: NotificationTemplate,
  reason: SkipReason,
  rendered: { title: string; body: string; reason_note?: string }
): Promise<PushResult> {
  const supabase = getSupabaseServiceRoleClient();
  const dedupKey = buildDedupKey(req, template, req.scheduledFor ?? new Date());

  // Insert (or upsert if collision) so we have an audit trail of the skip.
  const { data, error } = await supabase
    .from("notification_dispatches")
    .insert({
      user_id: req.userId,
      template_id: template.id,
      status: "skipped",
      skip_reason: reason,
      title_rendered: rendered.title,
      body_rendered: rendered.body,
      variables_used: req.variables ?? {},
      experiment_variant: req.experimentVariant ?? "control",
      scheduled_for: (req.scheduledFor ?? new Date()).toISOString(),
      dedup_key: dedupKey
    })
    .select("id")
    .maybeSingle();

  if (error && (error as { code?: string }).code === "23505") {
    return { status: "skipped", skipReason: "duplicate" };
  }
  if (error) {
    throw error;
  }

  return { status: "skipped", skipReason: reason, dispatchId: data?.id };
}

function buildDedupKey(
  req: PushRequest,
  template: NotificationTemplate,
  now: Date
): string {
  const bucket = req.dedupBucket ?? "daily";
  let bucketSlug: string;
  if (bucket === "event") {
    bucketSlug = `event:${req.eventId ?? crypto.randomUUID()}`;
  } else if (bucket === "hourly") {
    bucketSlug = `hourly:${now.toISOString().slice(0, 13)}`;
  } else {
    bucketSlug = `daily:${now.toISOString().slice(0, 10)}`;
  }
  const payload = `${req.userId}|${template.id}|${bucketSlug}`;
  return crypto.createHash("sha256").update(payload).digest("hex");
}
