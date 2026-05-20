-- ============================================================================
-- Cooksy — Subscription state tracking (Sprint 3 of the notifications system).
-- ----------------------------------------------------------------------------
-- Purpose:
--   The notifications crons need to know *when* a subscription expires,
--   whether it will auto-renew, and when a trial converted. `profiles`
--   only carries a boolean `is_premium`, which is not enough to power:
--     - cancelled_renewal_save_d-3  (subs expiring in ~3 days, renew off)
--     - lapsed_d7_value             (subs that expired ~7 days ago)
--     - welcome_paid_d0             (first renewal after a trial)
--
--   This table is the per-user subscription mirror, written exclusively
--   by the RevenueCat webhook handler.
--
-- How to apply:
--   - Supabase dashboard → SQL editor → paste → Run.
--   This migration is idempotent (safe to re-run).
-- ============================================================================

create table if not exists public.user_subscription_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- "trial" | "active" | "cancelled" | "expired" | "unknown"
  --   trial     → in a free-trial period, will convert unless cancelled
  --   active    → paying, auto-renew on
  --   cancelled → auto-renew OFF but still inside the paid period
  --   expired   → access has actually ended
  status text not null default 'unknown',
  product_id text,
  is_trial boolean not null default false,
  -- false once the user turns off auto-renew (RC CANCELLATION event).
  will_renew boolean not null default true,
  -- The instant access ends (or renews). From RC `expiration_at_ms`.
  current_period_end timestamptz,
  last_event_type text,
  -- Set the first time a trial converts to a paid renewal. Used to fire
  -- welcome_paid_d0 exactly once.
  trial_converted_at timestamptz,
  -- Set on the RC EXPIRATION event — anchors the lapsed_d7 win-back scan.
  expired_at timestamptz,
  -- Set on the RC CANCELLATION event — anchors the cancellation-save flow.
  cancelled_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Index for the "expiring in ~3 days, won't renew" cancellation-save scan.
create index if not exists user_subscription_state_period_end_idx
  on public.user_subscription_state(current_period_end)
  where will_renew = false;

-- Index for the "expired ~7 days ago" win-back scan.
create index if not exists user_subscription_state_expired_idx
  on public.user_subscription_state(expired_at)
  where status = 'expired';

alter table public.user_subscription_state enable row level security;

-- Users may read their own subscription state (handy for an in-app
-- "manage subscription" screen). Only the service-role webhook writes.
drop policy if exists "user_subscription_state_select_own" on public.user_subscription_state;
create policy "user_subscription_state_select_own"
  on public.user_subscription_state
  for select using (auth.uid() = user_id);

drop policy if exists "user_subscription_state_deny_writes" on public.user_subscription_state;
create policy "user_subscription_state_deny_writes"
  on public.user_subscription_state
  for all using (false) with check (false);
