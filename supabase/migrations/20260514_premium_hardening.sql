-- ============================================================================
-- Cooksy — Premium hardening migration
-- ----------------------------------------------------------------------------
-- Purpose:
--   1. Persist RevenueCat webhook deliveries for idempotency.
--   2. Track import quota usage server-side (the real source of truth —
--      the iOS client's ImportQuotaService is now an UX hint only).
--   3. Prevent users from flipping `profiles.is_premium` themselves.
--
-- How to apply:
--   - Supabase dashboard → SQL editor → paste this file → Run.
--   - OR via the Supabase CLI: `supabase db push`.
--   This migration is idempotent (safe to re-run).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. webhook_events — idempotency log for RevenueCat (and future) webhooks
-- ----------------------------------------------------------------------------
create table if not exists public.webhook_events (
  id text primary key,             -- RevenueCat event id (e.g. "RC-12345…")
  provider text not null,          -- "revenuecat" today, room for "stripe" later
  event_type text not null,        -- INITIAL_PURCHASE, RENEWAL, CANCELLATION, …
  payload jsonb not null,          -- raw payload, kept for debugging / replay
  processed_at timestamptz not null default now()
);

create index if not exists webhook_events_provider_idx
  on public.webhook_events(provider, event_type, processed_at desc);

alter table public.webhook_events enable row level security;

-- No client access whatsoever. Service role bypasses RLS.
drop policy if exists "webhook_events_deny_all" on public.webhook_events;
create policy "webhook_events_deny_all" on public.webhook_events
  for all using (false) with check (false);

-- ----------------------------------------------------------------------------
-- 2. import_quota_window — rolling 7-day import counter per user
-- ----------------------------------------------------------------------------
-- One row per `(user_id, window_start_date)`. We bucket by ISO week
-- (Monday-based) so the quota resets cleanly every Monday. This is
-- simpler than tracking individual import timestamps and indexes well.
create table if not exists public.import_quota_window (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_start_date date not null,         -- ISO week start (Monday)
  imports_used int not null default 0,
  last_import_at timestamptz,
  primary key (user_id, window_start_date)
);

create index if not exists import_quota_window_user_idx
  on public.import_quota_window(user_id, window_start_date desc);

alter table public.import_quota_window enable row level security;

-- Users can read their own usage (so the iOS app can show "3/5
-- imports used this week") but not write — only the backend can.
drop policy if exists "import_quota_window_select_own" on public.import_quota_window;
create policy "import_quota_window_select_own"
  on public.import_quota_window
  for select using (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 3. Lock down profiles.is_premium — clients cannot self-promote
-- ----------------------------------------------------------------------------
-- The existing "profiles_update_own" policy lets users update their own
-- row. Replace it with a policy that explicitly forbids them from
-- changing `is_premium` (the value can only be touched by the
-- service-role webhook handler). All other columns remain editable.
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles
  for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    -- The new value of is_premium must equal the existing one.
    -- (`is_premium` references the "new" row; we compare it to the
    --  current persisted value via a sub-select on the same row.)
    and is_premium = (
      select is_premium from public.profiles existing
      where existing.id = profiles.id
    )
  );

-- ----------------------------------------------------------------------------
-- 4. set_premium() RPC — single trusted entry point used by the webhook
-- ----------------------------------------------------------------------------
-- Even though the service-role key bypasses RLS, going through a
-- function keeps the contract explicit and gives us one obvious place
-- to audit if anything ever flips a user's premium status.
create or replace function public.set_premium(
  target_user_id uuid,
  next_value boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
    set is_premium = next_value,
        updated_at = now()
    where id = target_user_id;
end;
$$;

revoke all on function public.set_premium(uuid, boolean) from public;
revoke all on function public.set_premium(uuid, boolean) from anon;
revoke all on function public.set_premium(uuid, boolean) from authenticated;
-- Only service_role (the backend) can call this function.
grant execute on function public.set_premium(uuid, boolean) to service_role;

-- ----------------------------------------------------------------------------
-- 5. consume_import_quota() RPC — atomic check-and-increment
-- ----------------------------------------------------------------------------
-- Returns the row of the current window AFTER incrementing. Callers
-- compare `imports_used` to their plan limit (5 for free, 100 for
-- premium) to decide whether to proceed or 402. Atomic via row lock.
create or replace function public.consume_import_quota(
  target_user_id uuid,
  current_window_start date
)
returns table (
  imports_used int,
  last_import_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  insert into public.import_quota_window as q (user_id, window_start_date, imports_used, last_import_at)
  values (target_user_id, current_window_start, 1, now())
  on conflict (user_id, window_start_date) do update
    set imports_used = q.imports_used + 1,
        last_import_at = now()
  returning q.imports_used, q.last_import_at;
end;
$$;

revoke all on function public.consume_import_quota(uuid, date) from public;
revoke all on function public.consume_import_quota(uuid, date) from anon;
revoke all on function public.consume_import_quota(uuid, date) from authenticated;
grant execute on function public.consume_import_quota(uuid, date) to service_role;
