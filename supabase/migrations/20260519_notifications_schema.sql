-- ============================================================================
-- Cooksy — Notifications schema (Sprint 1 of the notifications system).
-- ----------------------------------------------------------------------------
-- Purpose:
--   1. Track APNs device tokens per user so the backend can target devices.
--   2. Store a versioned notification-template catalogue (titles, copy, FR).
--   3. Append-only event log fed by iOS + RevenueCat webhooks.
--   4. Dispatch log that records every send attempt (sent | skipped | failed)
--      with a deterministic dedup_key so re-runs are idempotent.
--   5. Per-user preference toggles (opt-out per category, RGPD-friendly).
--   6. Nightly user_segments_daily snapshot driving who-gets-what.
--   7. Extend profiles with last_active_at / timezone / locale / holdout_group
--      so the dispatcher can pick the right user, the right moment, and a
--      stable 5 % control group for incrementality measurement.
--
-- All tables are guarded by RLS. Service role bypasses RLS — every cron job
-- and the dispatcher use the service-role key.
--
-- How to apply:
--   - Supabase dashboard → SQL editor → paste this file → Run.
--   - OR `supabase db push` if you wire the CLI up.
--   This migration is idempotent (safe to re-run).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Extend profiles with activity + locale + holdout
-- ----------------------------------------------------------------------------
-- Adding these to profiles (not to a side table) keeps the segmentation
-- queries trivial. last_active_at is touched on every app.opened event;
-- timezone / locale default to FR but iOS will push the real values on
-- registration. holdout_group is sticky-per-user, decided once at signup.
alter table public.profiles
  add column if not exists last_active_at timestamptz,
  add column if not exists timezone text default 'Europe/Paris',
  add column if not exists locale text default 'fr-FR',
  add column if not exists holdout_group boolean;

-- Index for "give me dormant users" scans (cron F1/F3).
create index if not exists profiles_last_active_idx
  on public.profiles(last_active_at desc nulls last);

-- ----------------------------------------------------------------------------
-- 2. device_tokens — APNs targets, 1 user can have N devices (iPhone + iPad)
-- ----------------------------------------------------------------------------
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  apns_token text not null,
  -- Sandbox vs production matters at the APNs HTTP/2 transport level:
  -- sandbox tokens go to api.sandbox.push.apple.com, prod to api.push.apple.com.
  -- We default to "production"; debug builds will register with "sandbox".
  apns_environment text not null default 'production',
  device_model text,
  app_version text,
  os_version text,
  locale text default 'fr-FR',
  timezone text default 'Europe/Paris',
  -- "authorized" | "provisional" | "denied" | "ephemeral" | "unknown"
  push_authorization_status text default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  -- Set when APNs returns 410 Gone. We keep the row for audit but stop
  -- sending. If the user re-grants permission iOS will re-register and
  -- we'll upsert + clear disabled_at.
  disabled_at timestamptz,
  unique (user_id, apns_token)
);

create index if not exists device_tokens_user_idx
  on public.device_tokens(user_id)
  where disabled_at is null;

alter table public.device_tokens enable row level security;

-- Users can read their own tokens (so iOS can introspect). Inserts and
-- updates go through the backend service-role path only — APNs tokens
-- must never be writable by a regular client (would let an attacker
-- attach tokens to other users' accounts).
drop policy if exists "device_tokens_select_own" on public.device_tokens;
create policy "device_tokens_select_own"
  on public.device_tokens
  for select using (auth.uid() = user_id);

drop policy if exists "device_tokens_deny_writes" on public.device_tokens;
create policy "device_tokens_deny_writes"
  on public.device_tokens
  for all using (false) with check (false);

-- ----------------------------------------------------------------------------
-- 3. notification_templates — versioned copy catalogue
-- ----------------------------------------------------------------------------
-- One row per template (e.g. "trial_d5_reminder"). Copy is FR-first;
-- locale-specific columns will be added when we expand beyond FR (we'll
-- add body_en, title_en etc., or move to a templates_localized table).
create table if not exists public.notification_templates (
  id text primary key,                    -- e.g. "trial_d5_reminder"
  category text not null,                 -- onboarding | quota | trial | premium | dormant | lapsed | gift | milestone
  priority smallint not null check (priority between 0 and 3),
  -- false = utility (always sent, ignores marketing opt-outs and holdout).
  -- true  = marketing/promo (governed by per-user prefs and holdout).
  is_marketing boolean not null default true,
  is_active boolean not null default true,
  title_fr text not null,
  body_fr text not null,
  deep_link text,                         -- e.g. "cooksy://paywall?source=quota_push"
  -- Variables we want substituted into title/body, e.g. ["recipe_title", "prep_time"].
  -- Validates the renderer's input.
  variables jsonb not null default '[]',
  -- If a variable is missing, fall back to another template id. Pattern
  -- used when "mealtime_personal" can't find a recipe → fallback to a
  -- generic copy.
  fallback_template_id text references public.notification_templates(id),
  cooldown_days smallint not null default 0,
  version smallint not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.notification_templates enable row level security;

-- Templates are public-readable (the iOS settings screen lists categories
-- pulled from this table), no client writes.
drop policy if exists "notification_templates_select_all" on public.notification_templates;
create policy "notification_templates_select_all"
  on public.notification_templates
  for select using (true);

drop policy if exists "notification_templates_deny_writes" on public.notification_templates;
create policy "notification_templates_deny_writes"
  on public.notification_templates
  for all using (false) with check (false);

-- ----------------------------------------------------------------------------
-- 4. notification_events — append-only log of every signal we care about
-- ----------------------------------------------------------------------------
-- Sources: iOS (app.opened, paywall.shown, paywall.closed_without_purchase,
-- cook_session.completed), backend (recipe.imported, quota.reached),
-- RevenueCat webhooks (trial.started, subscription.cancelled, etc.).
--
-- This is *the* feed the dispatcher consumes. Never delete rows — purge by
-- partition or TTL job later if size matters (events stay small).
create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  event_data jsonb not null default '{}',
  occurred_at timestamptz not null default now()
);

create index if not exists notification_events_user_idx
  on public.notification_events(user_id, event_type, occurred_at desc);

create index if not exists notification_events_type_idx
  on public.notification_events(event_type, occurred_at desc);

alter table public.notification_events enable row level security;

drop policy if exists "notification_events_deny_all" on public.notification_events;
create policy "notification_events_deny_all"
  on public.notification_events
  for all using (false) with check (false);

-- ----------------------------------------------------------------------------
-- 5. notification_dispatches — one row per send *attempt*
-- ----------------------------------------------------------------------------
-- status:
--   queued       → eligibility passed, dedup_key inserted, about to send
--   sent         → APNs accepted (HTTP 200)
--   skipped      → eligibility failed (quiet hours, cooldown, holdout, mute…)
--   failed       → APNs rejected (BadDeviceToken, Unregistered, 5xx)
--   delivered    → optional, set via NotificationServiceExtension beacon
--   opened       → iOS reported the user expanded the banner
--   tapped       → iOS reported a deep-link tap
--
-- dedup_key prevents re-sending the same template to the same user in the
-- same time bucket. Format: sha256(user_id||template_id||bucket).
create table if not exists public.notification_dispatches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  template_id text not null references public.notification_templates(id),
  device_token_id uuid references public.device_tokens(id) on delete set null,
  status text not null,
  skip_reason text,
  apns_status_code smallint,
  apns_response jsonb,
  title_rendered text,
  body_rendered text,
  variables_used jsonb,
  experiment_variant text default 'control',
  scheduled_for timestamptz,
  sent_at timestamptz,
  delivered_at timestamptz,
  opened_at timestamptz,
  tapped_at timestamptz,
  created_at timestamptz not null default now(),
  -- The unique constraint is what enforces "send-once-per-bucket". The
  -- dispatcher computes the key, tries an insert, and if it collides we
  -- know we already handled this event/user/template combination.
  dedup_key text not null unique
);

create index if not exists notification_dispatches_user_sent_idx
  on public.notification_dispatches(user_id, sent_at desc)
  where sent_at is not null;

create index if not exists notification_dispatches_template_idx
  on public.notification_dispatches(template_id, sent_at desc);

create index if not exists notification_dispatches_scheduled_idx
  on public.notification_dispatches(scheduled_for)
  where status = 'queued' and sent_at is null;

alter table public.notification_dispatches enable row level security;

-- Users can read their own dispatch history (useful for an in-app "notif
-- history" screen later, and required for the iOS opened/tapped beacons
-- to look up their own dispatch by id).
drop policy if exists "notification_dispatches_select_own" on public.notification_dispatches;
create policy "notification_dispatches_select_own"
  on public.notification_dispatches
  for select using (auth.uid() = user_id);

drop policy if exists "notification_dispatches_deny_writes" on public.notification_dispatches;
create policy "notification_dispatches_deny_writes"
  on public.notification_dispatches
  for all using (false) with check (false);

-- ----------------------------------------------------------------------------
-- 6. notification_preferences — per-category opt-outs
-- ----------------------------------------------------------------------------
create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  -- Master switch for marketing content. If false, the dispatcher
  -- skips every template where is_marketing = true, even if individual
  -- category toggles below say enabled. Utilities (trial reminders,
  -- cancellation saves) ignore this flag.
  marketing_enabled boolean not null default true,
  promo_enabled boolean not null default true,
  suggestion_enabled boolean not null default true,
  reminder_enabled boolean not null default true,
  digest_enabled boolean not null default true,
  -- Wildcard per-category overrides keyed by template.category. Lets us
  -- add new categories without DDL.
  category_overrides jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences_select_own" on public.notification_preferences;
create policy "notification_preferences_select_own"
  on public.notification_preferences
  for select using (auth.uid() = user_id);

-- Users can update their own prefs from the in-app settings screen.
drop policy if exists "notification_preferences_upsert_own" on public.notification_preferences;
create policy "notification_preferences_upsert_own"
  on public.notification_preferences
  for insert with check (auth.uid() = user_id);

drop policy if exists "notification_preferences_update_own" on public.notification_preferences;
create policy "notification_preferences_update_own"
  on public.notification_preferences
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 7. user_segments_daily — refreshed nightly by segmentationCron
-- ----------------------------------------------------------------------------
-- The dispatcher reads `user_segments_daily where snapshot_date = current_date`
-- and indexes lifecycle_stage to scan dormants / trial users / etc. fast.
-- One row per (user, day). Keep ~30 days for diffing, then prune.
create table if not exists public.user_segments_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  snapshot_date date not null default current_date,
  lifecycle_stage text not null,         -- new_install | activated_free | engaged_free | quota_blocked_free | in_trial | paid_active | paid_dormant | churn_risk_paid | lapsed_premium | dormant_short | dormant_long | ghost
  importer_type text,                    -- light | regular | power
  use_type text,                         -- import_only | import_cook | import_plan
  time_of_day_pref text,                 -- morning | lunch | evening | weekend
  source_affinity text,                  -- tiktok | instagram | mixed
  last_active_at timestamptz,
  imports_last_7d int not null default 0,
  imports_last_30d int not null default 0,
  cook_sessions_last_30d int not null default 0,
  holdout_group boolean not null default false,
  primary key (user_id, snapshot_date)
);

create index if not exists user_segments_daily_stage_idx
  on public.user_segments_daily(snapshot_date, lifecycle_stage);

alter table public.user_segments_daily enable row level security;

drop policy if exists "user_segments_daily_deny_all" on public.user_segments_daily;
create policy "user_segments_daily_deny_all"
  on public.user_segments_daily
  for all using (false) with check (false);

-- ----------------------------------------------------------------------------
-- 8. Holdout assignment helper — stable per-user 5 % control group
-- ----------------------------------------------------------------------------
-- Deterministic: hash the user id and check if it lands in the bottom 5 %.
-- Stored on profiles.holdout_group at signup, never changed thereafter so
-- the same user is always in/out of the test group for the lifetime of
-- their account. Pure function so it can be called from triggers and from
-- the segmentation cron.
create or replace function public.compute_holdout_group(target_user_id uuid)
returns boolean
language sql
immutable
as $$
  -- ~5 % bucket. We use the first 4 hex chars (16 bits = 0..65535) and
  -- check if < 3277 (5 % of 65536). Stable, no PRNG.
  select (('x' || substr(md5(target_user_id::text), 1, 4))::bit(16))::int < 3277;
$$;

-- Trigger: at insert into profiles, if holdout_group is null, assign it.
-- (The existing handle_new_user trigger creates profiles rows from
-- auth.users; the function ran before this column existed.)
create or replace function public.assign_holdout_group()
returns trigger
language plpgsql
as $$
begin
  if new.holdout_group is null then
    new.holdout_group := public.compute_holdout_group(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_assign_holdout on public.profiles;
create trigger profiles_assign_holdout
  before insert on public.profiles
  for each row execute function public.assign_holdout_group();

-- Backfill: assign holdout to existing users who don't have one.
update public.profiles
  set holdout_group = public.compute_holdout_group(id)
  where holdout_group is null;

-- ----------------------------------------------------------------------------
-- 9. View — quick perf dashboard for the last 7 days
-- ----------------------------------------------------------------------------
-- Used for "is template X dying / blowing up". Run from Supabase SQL editor.
create or replace view public.notification_template_perf_7d as
select
  template_id,
  count(*) filter (where status in ('sent', 'delivered', 'opened', 'tapped')) as sent,
  count(*) filter (where opened_at is not null) as opened,
  count(*) filter (where tapped_at is not null) as tapped,
  count(*) filter (where status = 'skipped') as skipped,
  count(*) filter (where status = 'failed') as failed,
  round(
    100.0 * count(*) filter (where opened_at is not null)
    / nullif(count(*) filter (where status in ('sent', 'delivered', 'opened', 'tapped')), 0),
    1
  ) as open_rate_pct,
  round(
    100.0 * count(*) filter (where tapped_at is not null)
    / nullif(count(*) filter (where status in ('sent', 'delivered', 'opened', 'tapped')), 0),
    1
  ) as ctr_pct
from public.notification_dispatches
where created_at > now() - interval '7 days'
group by template_id
order by sent desc nulls last;

-- ============================================================================
-- DONE. Next migration (20260519_notifications_seed.sql) inserts the v1
-- catalogue of templates. Keeping schema and seed separate so each can
-- evolve independently (we'll add templates often, schema rarely).
-- ============================================================================
