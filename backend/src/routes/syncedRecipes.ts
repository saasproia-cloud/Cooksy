import type { FastifyInstance } from "fastify";
import { z } from "zod";

import { requireAuth } from "../middleware/auth.js";
import { getSupabaseServiceRoleClient } from "../config/supabase.js";

/**
 * /api/recipes/* — cloud sync of the local Recipe library.
 *
 * Why a single jsonb column instead of a full relational schema?
 * The iOS Recipe model is rich (ingredients, steps, nutrition, books,
 * meal plan refs) and evolves fast. Keeping the payload opaque on the
 * server side means iOS can ship new fields without a backend release.
 * Search and analytics over the library is run client-side.
 *
 *   GET    /api/recipes               → pull all non-deleted recipes
 *   POST   /api/recipes/upsert        → push one recipe (single payload)
 *   POST   /api/recipes/upsert/batch  → push many in one round-trip
 *   DELETE /api/recipes/:recipeId     → soft-delete (tombstone)
 */

const upsertSchema = z.object({
  recipeId: z.string().uuid(),
  payload: z.record(z.unknown()),
  // The iOS-side updatedAt for the recipe — used as a tie-breaker if
  // we ever do conflict detection. For now last-write-wins.
  updatedAt: z.string().datetime().optional()
});

const batchUpsertSchema = z.object({
  recipes: z.array(upsertSchema).min(1).max(200)
});

export async function registerSyncedRecipesRoutes(app: FastifyInstance): Promise<void> {
  // Pull — initial hydration after sign-in (or any sync attempt).
  app.get(
    "/api/recipes",
    { preHandler: requireAuth },
    async (request, reply) => {
      const supabase = getSupabaseServiceRoleClient();
      const { data, error } = await supabase
        .from("synced_recipes")
        .select("recipe_id, payload, updated_at")
        .eq("user_id", request.user!.id)
        .is("deleted_at", null)
        .order("updated_at", { ascending: false });
      if (error) {
        request.log.error(
          { event: "recipes.pull.failed", message: error.message },
          "synced_recipes pull failed"
        );
        reply.status(500);
        return { error: "pull_failed" };
      }
      return {
        recipes: (data ?? []).map((row) => ({
          recipeId: row.recipe_id,
          payload: row.payload,
          updatedAt: row.updated_at
        }))
      };
    }
  );

  // Single upsert — called on every add/update on iOS.
  app.post(
    "/api/recipes/upsert",
    { preHandler: requireAuth },
    async (request, reply) => {
      const body = upsertSchema.parse(request.body);
      const supabase = getSupabaseServiceRoleClient();
      const { error } = await supabase
        .from("synced_recipes")
        .upsert(
          {
            user_id: request.user!.id,
            recipe_id: body.recipeId,
            payload: body.payload,
            updated_at: body.updatedAt ?? new Date().toISOString(),
            deleted_at: null
          },
          { onConflict: "user_id,recipe_id" }
        );
      if (error) {
        reply.status(500);
        return { error: "upsert_failed", message: error.message };
      }
      return { ok: true };
    }
  );

  // Batch upsert — initial migration of an existing local library, or
  // catch-up when the app comes back online after a stretch offline.
  app.post(
    "/api/recipes/upsert/batch",
    { preHandler: requireAuth },
    async (request, reply) => {
      const body = batchUpsertSchema.parse(request.body);
      const supabase = getSupabaseServiceRoleClient();
      const rows = body.recipes.map((r) => ({
        user_id: request.user!.id,
        recipe_id: r.recipeId,
        payload: r.payload,
        updated_at: r.updatedAt ?? new Date().toISOString(),
        deleted_at: null
      }));
      const { error } = await supabase
        .from("synced_recipes")
        .upsert(rows, { onConflict: "user_id,recipe_id" });
      if (error) {
        reply.status(500);
        return { error: "batch_upsert_failed", message: error.message };
      }
      return { ok: true, count: rows.length };
    }
  );

  // Soft-delete — keeps the tombstone so other devices can prune their
  // local copy. The row is GC'd after 30 d (separate job).
  app.delete<{ Params: { recipeId: string } }>(
    "/api/recipes/:recipeId",
    { preHandler: requireAuth },
    async (request, reply) => {
      const { recipeId } = request.params;
      if (!/^[0-9a-fA-F-]{36}$/.test(recipeId)) {
        reply.status(400);
        return { error: "invalid_recipe_id" };
      }
      const supabase = getSupabaseServiceRoleClient();
      const { error } = await supabase
        .from("synced_recipes")
        .update({ deleted_at: new Date().toISOString() })
        .eq("user_id", request.user!.id)
        .eq("recipe_id", recipeId);
      if (error) {
        reply.status(500);
        return { error: "delete_failed" };
      }
      return { ok: true };
    }
  );
}
