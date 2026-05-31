-- ============================================================================
-- Cooksy — Premium Chat Assistant (Sprint).
-- ----------------------------------------------------------------------------
-- Purpose:
--   1. Persist 1 chat thread per (user_id, recipe_id) so the assistant
--      keeps its history between sessions (Premium UX promise).
--   2. Persist every message (user + assistant) with its structured
--      payload (suggestions, pending_modification) so the iOS sheet can
--      rehydrate exactly what the user left behind.
--   3. Track every applied recipe modification (ingredient swap) with a
--      snapshot of the ingredients it touched, so the ↺ button can revert
--      atomically and independently of other swaps.
--   4. Add `allergens` to recipes for allergen-aware suggestions and
--      recomputation after a swap. Per-ingredient `origin*` fields live
--      inside the existing ingredients jsonb (no schema change there).
--
-- All tables are RLS-guarded. Service role bypasses RLS — the chat backend
-- uses the service-role key.
--
-- How to apply:
--   - Supabase dashboard → SQL editor → paste this file → Run.
--   - OR `supabase db push` if you wire the CLI up.
-- This migration is idempotent (safe to re-run).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. recipes.allergens — string array, optional.
-- Kept even though the iOS app does not yet sync recipes to Supabase: a
-- future sync pass will need this column, and it's idempotent today.
-- ----------------------------------------------------------------------------
alter table public.recipes
  add column if not exists allergens jsonb;

-- ----------------------------------------------------------------------------
-- 2. chat_threads — 1 row per (user, recipe). 1:N → chat_messages.
-- NOTE: recipe_id is NOT a FK because the iOS app currently keeps recipes
--       in a local JSON library (never written to public.recipes). A FK
--       here would break every insert. We accept that thread rows can
--       outlive their recipe; a future migration can backfill the FK once
--       the recipe sync ships.
-- ----------------------------------------------------------------------------
create table if not exists public.chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  unique (user_id, recipe_id)
);

create index if not exists chat_threads_user_idx
  on public.chat_threads(user_id, last_message_at desc);

-- ----------------------------------------------------------------------------
-- 3. chat_messages — append-only conversation log
-- ----------------------------------------------------------------------------
-- role  : 'user' | 'assistant' | 'system'
-- content_text         : the rendered bubble copy
-- suggestions_json     : { kind, target?, options: [{id,label,shortImpact}] }
-- pending_modification : { modificationId, summary, diff: {...} }
-- ----------------------------------------------------------------------------
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null,
  role text not null check (role in ('user','assistant','system')),
  content_text text,
  suggestions_json jsonb,
  pending_modification_json jsonb,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_thread_idx
  on public.chat_messages(thread_id, created_at);
create index if not exists chat_messages_user_idx
  on public.chat_messages(user_id, created_at desc);

-- Bump the parent thread's last_message_at on insert.
create or replace function public.touch_chat_thread()
returns trigger
language plpgsql
as $$
begin
  update public.chat_threads
     set last_message_at = new.created_at
   where id = new.thread_id;
  return new;
end;
$$;

drop trigger if exists chat_messages_touch_thread on public.chat_messages;
create trigger chat_messages_touch_thread
  after insert on public.chat_messages
  for each row execute function public.touch_chat_thread();

-- ----------------------------------------------------------------------------
-- 4. recipe_modifications — audit log + revert snapshots
-- ----------------------------------------------------------------------------
-- kind     : 'ingredient_swap' | 'scale_portions' (extensible)
-- payload  : the full diff applied. For ingredient_swap:
--   {
--     ingredientId: uuid,
--     before: { name, amount, unit },
--     after:  { name, amount, unit },
--     stepRewrites: [{ stepId, beforeDetail, afterDetail }],
--     nutritionBefore?: {...}, nutritionAfter?: {...},
--     allergensBefore?: [...], allergensAfter?: [...]
--   }
-- ----------------------------------------------------------------------------
create table if not exists public.recipe_modifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null,
  thread_id uuid references public.chat_threads(id) on delete set null,
  kind text not null check (kind in ('ingredient_swap','scale_portions')),
  summary text not null,
  payload_jsonb jsonb not null,
  applied_at timestamptz not null default now(),
  reverted_at timestamptz
);

create index if not exists recipe_modifications_recipe_idx
  on public.recipe_modifications(recipe_id, applied_at desc);
create index if not exists recipe_modifications_active_idx
  on public.recipe_modifications(recipe_id)
  where reverted_at is null;

-- ----------------------------------------------------------------------------
-- 5. RLS
-- ----------------------------------------------------------------------------
alter table public.chat_threads enable row level security;
alter table public.chat_messages enable row level security;
alter table public.recipe_modifications enable row level security;

drop policy if exists "chat_threads_all_own" on public.chat_threads;
create policy "chat_threads_all_own" on public.chat_threads
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "chat_messages_all_own" on public.chat_messages;
create policy "chat_messages_all_own" on public.chat_messages
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "recipe_modifications_all_own" on public.recipe_modifications;
create policy "recipe_modifications_all_own" on public.recipe_modifications
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 6. Premium rate-limit counter (per user per hour) — defensive ceiling
--     enforced inside the chat handler. 60 messages / hour / Premium user is
--     well above any human conversation rhythm but caps a runaway loop.
-- ----------------------------------------------------------------------------
create table if not exists public.chat_rate_window (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_start_hour timestamptz not null,
  messages_sent int not null default 0,
  primary key (user_id, window_start_hour)
);

create index if not exists chat_rate_window_user_idx
  on public.chat_rate_window(user_id, window_start_hour desc);

alter table public.chat_rate_window enable row level security;
-- No client policies — service-role only.

create or replace function public.consume_chat_quota(
  target_user_id uuid,
  window_hour timestamptz,
  hourly_cap int
) returns table (messages_sent int, allowed boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count int;
begin
  insert into public.chat_rate_window (user_id, window_start_hour, messages_sent)
  values (target_user_id, window_hour, 1)
  on conflict (user_id, window_start_hour)
    do update set messages_sent = public.chat_rate_window.messages_sent + 1
  returning public.chat_rate_window.messages_sent into current_count;

  return query select current_count, current_count <= hourly_cap;
end;
$$;
