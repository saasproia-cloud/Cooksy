-- ============================================================================
-- Cooksy — Phase 2 (chat add_components) + Phase 3 (cloud sync recipes).
-- ----------------------------------------------------------------------------
-- 1. Allow 'add_components' kind in recipe_modifications so the chat
--    assistant can audit a sauce/side addition.
-- 2. Add a synced_recipes table — one row per (user, recipe). Stores the
--    full Recipe JSON as a jsonb blob so a reinstall + Apple ID sign-in
--    rehydrates everything (recipes, books, meal plan) without losing
--    anything.
--
-- Re-run safe (every statement is guarded).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. recipe_modifications.kind — accept 'add_components'
-- ----------------------------------------------------------------------------
alter table public.recipe_modifications
  drop constraint if exists recipe_modifications_kind_check;
alter table public.recipe_modifications
  add constraint recipe_modifications_kind_check
  check (kind in ('ingredient_swap', 'scale_portions', 'add_components'));

-- ----------------------------------------------------------------------------
-- 2. synced_recipes — one row per (user_id, recipe_id)
-- ----------------------------------------------------------------------------
-- payload holds the entire Recipe Codable blob produced by the iOS app.
-- Cheapest viable cloud-sync surface: no separate ingredients/steps
-- tables to keep in lock-step with the iOS Recipe model. The trade-off
-- is search-by-ingredient on the server is jsonb-only, which we don't
-- need yet (search runs client-side on the local library).
create table if not exists public.synced_recipes (
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null,
  payload jsonb not null,
  -- Last-write-wins conflict resolution. The iOS app sends the recipe's
  -- own updatedAt (it stamps every edit). On pull, the most recent
  -- payload wins.
  updated_at timestamptz not null default now(),
  -- Soft-delete flag — when the user deletes a recipe locally, we keep
  -- the row briefly so other devices can pick up the tombstone, then
  -- the GC sweeps rows where deleted_at < now() - 30 d.
  deleted_at timestamptz,
  primary key (user_id, recipe_id)
);

create index if not exists synced_recipes_user_updated_idx
  on public.synced_recipes(user_id, updated_at desc)
  where deleted_at is null;

alter table public.synced_recipes enable row level security;

-- Users own their recipes; service role bypasses RLS.
drop policy if exists "synced_recipes_select_own" on public.synced_recipes;
create policy "synced_recipes_select_own"
  on public.synced_recipes
  for select using (auth.uid() = user_id);

-- Writes go through the backend service-role only (we want the upsert
-- + last-write-wins logic centralised, and we plan to add per-payload
-- validation later).
drop policy if exists "synced_recipes_deny_writes" on public.synced_recipes;
create policy "synced_recipes_deny_writes"
  on public.synced_recipes
  for all using (false) with check (false);
