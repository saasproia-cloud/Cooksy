import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../middleware/auth.js";
import { getSupabaseServiceRoleClient } from "../config/supabase.js";

/**
 * /api/events — lightweight client-side event beacon.
 *
 * The iOS app posts a small list of events here (typically batched on
 * background, sometimes single events on important transitions) so the
 * notifications dispatcher and segmentation cron have signal to work
 * with.
 *
 * Tracked event types (extensible):
 *   - app.opened
 *   - paywall.shown
 *   - paywall.closed_without_purchase
 *   - cook_session.completed
 *   - meal_plan.created
 *
 * We bypass strict schema-per-event-type to keep the iOS side simple
 * and DDL-free as we iterate.
 */

const eventTypeSchema = z.enum([
  "app.opened",
  "paywall.shown",
  "paywall.closed_without_purchase",
  "cook_session.completed",
  "meal_plan.created",
  "import.attempted",
  "settings.notifications_changed"
]);

const singleEventSchema = z.object({
  event_type: eventTypeSchema,
  event_data: z.record(z.unknown()).optional(),
  occurred_at: z.string().datetime().optional()
});

const batchEventsSchema = z.object({
  events: z.array(singleEventSchema).min(1).max(50)
});

export async function registerEventRoutes(app: FastifyInstance): Promise<void> {
  app.post(
    "/api/events",
    { preHandler: requireAuth },
    async (request, reply) => {
      const userId = request.user!.id;
      const body = batchEventsSchema.parse(request.body);
      const supabase = getSupabaseServiceRoleClient();

      const rows = body.events.map((evt) => ({
        user_id: userId,
        event_type: evt.event_type,
        event_data: evt.event_data ?? {},
        occurred_at: evt.occurred_at ?? new Date().toISOString()
      }));

      const { error } = await supabase
        .from("notification_events")
        .insert(rows);

      if (error) {
        request.log.error(
          { event: "events.ingest.failed", message: error.message },
          "Event ingestion failed"
        );
        reply.status(500);
        return { error: "ingest_failed" };
      }

      // Side-effect: if at least one app.opened event came through, bump
      // profiles.last_active_at so dormant scans stop targeting them.
      const hasOpen = body.events.some((evt) => evt.event_type === "app.opened");
      if (hasOpen) {
        await supabase
          .from("profiles")
          .update({ last_active_at: new Date().toISOString() })
          .eq("id", userId);
      }

      return { ok: true, ingested: rows.length };
    }
  );
}
