import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../middleware/auth.js";
import { getSupabaseServiceRoleClient } from "../config/supabase.js";

/**
 * /api/devices/* — APNs token registry.
 *
 *   POST   /api/devices/register   → upsert a device token for the user
 *   DELETE /api/devices/:token     → mark a device token disabled
 *                                    (used on sign-out / permission revoked)
 *
 * Tokens are 64-character hex strings. We don't validate length strictly
 * — Apple has changed the format twice since 2014 — but we cap at 200
 * chars to prevent stray garbage from filling the column.
 */

const registerSchema = z.object({
  apns_token: z.string().min(20).max(200),
  apns_environment: z.enum(["production", "sandbox"]).default("production"),
  device_model: z.string().max(80).optional(),
  app_version: z.string().max(40).optional(),
  os_version: z.string().max(40).optional(),
  locale: z.string().max(20).optional(),
  timezone: z.string().max(60).optional(),
  push_authorization_status: z
    .enum(["authorized", "provisional", "denied", "ephemeral", "unknown"])
    .default("unknown")
});

export async function registerDeviceRoutes(app: FastifyInstance): Promise<void> {
  app.post(
    "/api/devices/register",
    { preHandler: requireAuth },
    async (request, reply) => {
      const body = registerSchema.parse(request.body);
      const supabase = getSupabaseServiceRoleClient();
      const userId = request.user!.id;

      // Upsert by (user_id, apns_token). If the same device re-registers
      // (permission flip, app reinstall), we update last_seen_at and
      // clear disabled_at so future pushes resume.
      const { data, error } = await supabase
        .from("device_tokens")
        .upsert(
          {
            user_id: userId,
            apns_token: body.apns_token,
            apns_environment: body.apns_environment,
            device_model: body.device_model ?? null,
            app_version: body.app_version ?? null,
            os_version: body.os_version ?? null,
            locale: body.locale ?? "fr-FR",
            timezone: body.timezone ?? "Europe/Paris",
            push_authorization_status: body.push_authorization_status,
            last_seen_at: new Date().toISOString(),
            disabled_at: null,
            updated_at: new Date().toISOString()
          },
          { onConflict: "user_id,apns_token" }
        )
        .select("id")
        .single();

      if (error) {
        request.log.error(
          { event: "devices.register.failed", message: error.message },
          "Device token registration failed"
        );
        reply.status(500);
        return { error: "registration_failed" };
      }

      // Also touch the user's profile timezone/locale so segmentation
      // queries can use the latest known device hints.
      if (body.timezone || body.locale) {
        await supabase
          .from("profiles")
          .update({
            ...(body.timezone ? { timezone: body.timezone } : {}),
            ...(body.locale ? { locale: body.locale } : {})
          })
          .eq("id", userId);
      }

      return { id: data.id, ok: true };
    }
  );

  app.delete<{ Params: { token: string } }>(
    "/api/devices/:token",
    { preHandler: requireAuth },
    async (request, reply) => {
      const token = request.params.token;
      if (!token || token.length < 20) {
        reply.status(400);
        return { error: "invalid_token" };
      }
      const supabase = getSupabaseServiceRoleClient();
      const { error } = await supabase
        .from("device_tokens")
        .update({ disabled_at: new Date().toISOString() })
        .eq("user_id", request.user!.id)
        .eq("apns_token", token);
      if (error) {
        reply.status(500);
        return { error: "disable_failed" };
      }
      return { ok: true };
    }
  );
}
