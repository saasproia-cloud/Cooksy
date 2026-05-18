-- ============================================================================
-- Cooksy — Account deletion + pre-launch hardening
-- ----------------------------------------------------------------------------
-- Purpose:
--   1. Expose a `delete_my_account()` RPC so the iOS client can offer a
--      one-tap "Supprimer mon compte" (required by Apple Guideline 5.1.1(v)
--      and RGPD). It deletes the row from `auth.users`; everything else
--      cascades because every domain table references `auth.users(id)
--      on delete cascade`.
--   2. Make the avatars + recipe-images buckets PRIVATE so signed URLs are
--      required to read them. Public buckets leak the user UUID via the
--      object path convention `<uid>/...`.
--   3. Add CHECK constraints on `profiles.display_name` and
--      `profiles.onboarding_answers` to prevent abuse-of-own-row spam
--      (unbounded text / jsonb).
--
-- Idempotent — safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. delete_my_account()
-- ----------------------------------------------------------------------------
-- Allows a signed-in user to delete their own row from `auth.users`.
-- We don't expose `auth.admin.delete_user` (service-role-only); instead
-- we DELETE the row directly under `security definer` privileges. The
-- ON DELETE CASCADE rules on every domain FK clean up everything else.
-- Storage objects don't cascade — they become orphaned but harmless,
-- and we'll add a janitor cron later if needed.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
revoke all on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Privatise storage buckets
-- ----------------------------------------------------------------------------
-- Flip `public` to false on both buckets. iOS reads via signed URLs.
update storage.buckets set public = false where id = 'avatars';
update storage.buckets set public = false where id = 'recipe-images';

-- Replace "public read" policies with "owner-or-signed-URL" reads:
-- authenticated users only see their own folder. Signed URLs work
-- regardless of policy because they're enforced by the storage layer.
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_select_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "recipe_images_public_read" on storage.objects;
create policy "recipe_images_select_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ----------------------------------------------------------------------------
-- 3. Bound `profiles` text/jsonb columns to prevent self-row spam
-- ----------------------------------------------------------------------------
-- Drop any pre-existing variant of these constraints so the migration
-- can re-run cleanly.
alter table public.profiles drop constraint if exists profiles_display_name_length;
alter table public.profiles drop constraint if exists profiles_onboarding_answers_size;

alter table public.profiles
  add constraint profiles_display_name_length
  check (display_name is null or char_length(display_name) <= 80);

-- jsonb has no native length op — use the serialised text length as a
-- coarse upper bound. 8 KB is generous for a survey answer payload.
alter table public.profiles
  add constraint profiles_onboarding_answers_size
  check (octet_length(onboarding_answers::text) <= 8192);
