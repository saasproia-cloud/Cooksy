import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../middleware/auth.js";
import { getSupabaseServiceRoleClient } from "../config/supabase.js";

/**
 * /api/notifications/* — user preferences + open/tap beacons.
 *
 *   GET    /api/notifications/preferences        → read prefs (or defaults)
 *   POST   /api/notifications/preferences        → upsert prefs
 *   POST   /api/notifications/:dispatchId/opened → beacon when user taps a push
 */

const prefsSchema = z.object({
  marketing_enabled: z.boolean().optional(),
  promo_enabled: z.boolean().optional(),
  suggestion_enabled: z.boolean().optional(),
  reminder_enabled: z.boolean().optional(),
  digest_enabled: z.boolean().optional(),
  category_overrides: z.record(z.boolean()).optional()
});

export async function registerNotificationPrefsRoutes(
  app: FastifyInstance
): Promise<void> {
  app.get(
    "/api/notifications/preferences",
    { preHandler: requireAuth },
    async (request) => {
      const supabase = getSupabaseServiceRoleClient();
      const { data } = await supabase
        .from("notification_preferences")
        .select(
          "marketing_enabled, promo_enabled, suggestion_enabled, reminder_enabled, digest_enabled, category_overrides"
        )
        .eq("user_id", request.user!.id)
        .maybeSingle();

      // First-launch users have no row yet — return the defaults so the
      // iOS settings screen can render without a round-trip.
      return (
        data ?? {
          marketing_enabled: true,
          promo_enabled: true,
          suggestion_enabled: true,
          reminder_enabled: true,
          digest_enabled: true,
          category_overrides: {}
        }
      );
    }
  );

  app.post(
    "/api/notifications/preferences",
    { preHandler: requireAuth },
    async (request, reply) => {
      const body = prefsSchema.parse(request.body);
      const supabase = getSupabaseServiceRoleClient();

      const { error } = await supabase
        .from("notification_preferences")
        .upsert(
          {
            user_id: request.user!.id,
            ...body,
            updated_at: new Date().toISOString()
          },
          { onConflict: "user_id" }
        );

      if (error) {
        request.log.error(
          { event: "notif.prefs.upsert.failed", message: error.message },
          "Notification prefs upsert failed"
        );
        reply.status(500);
        return { error: "upsert_failed" };
      }
      return { ok: true };
    }
  );

  // Open / tap beacons. The iOS NotificationsCenter calls this when the
  // user taps a push (or the OS reports it expanded), passing the
  // dispatch_id we round-tripped in customData.cooksy_dispatch_id.
  app.post<{ Params: { dispatchId: string }; Body: { event: "opened" | "tapped" } }>(
    "/api/notifications/:dispatchId/beacon",
    { preHandler: requireAuth },
    async (request, reply) => {
      const { dispatchId } = request.params;
      const event = request.body?.event ?? "opened";
      if (!dispatchId || dispatchId.length < 8) {
        reply.status(400);
        return { error: "invalid_dispatch_id" };
      }

      const supabase = getSupabaseServiceRoleClient();
      // Update only if the dispatch belongs to this user. RLS won't
      // protect us through the service-role client, so we double-check.
      const patch: Record<string, string> =
        event === "tapped"
          ? { tapped_at: new Date().toISOString(), status: "tapped" }
          : { opened_at: new Date().toISOString(), status: "opened" };

      const { error } = await supabase
        .from("notification_dispatches")
        .update(patch)
        .eq("id", dispatchId)
        .eq("user_id", request.user!.id);

      if (error) {
        reply.status(500);
        return { error: "beacon_failed" };
      }
      return { ok: true };
    }
  );
}
