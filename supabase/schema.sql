-- ============================================================================
-- Cooksy — Supabase initial schema
-- Run once in the Supabase SQL editor. Idempotent (safe to re-run).
-- ============================================================================

create extension if not exists "uuid-ossp";

-- ============================================================================
-- profiles (1:1 with auth.users)
-- ============================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  is_premium boolean not null default false,
  onboarding_completed_at timestamptz,
  onboarding_answers jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Backfill column for profiles tables created before onboarding_answers existed.
alter table public.profiles
  add column if not exists onboarding_answers jsonb not null default '{}'::jsonb;

-- Auto-create a profile row whenever a new auth user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- recipe_books — user-created collections of recipes
-- ============================================================================
create table if not exists public.recipe_books (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  kind text not null default 'collection' check (kind in ('collection','uncategorized')),
  preview_style text not null default 'neutral' check (preview_style in ('neutral','featured','softBlue')),
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists recipe_books_user_id_idx on public.recipe_books(user_id);

-- ============================================================================
-- recipes — one row per imported/created recipe
-- Structured fields (details, nutrition, ingredients, steps) are stored as
-- JSONB to mirror the Swift Codable models exactly. This preserves section
-- structure (marinade, sauce, assembly, etc.) without flattening.
-- ============================================================================
create table if not exists public.recipes (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid references public.recipe_books(id) on delete set null,
  title text not null,
  source_url text,
  creator_handle text,
  external_rating numeric(3,2),
  external_rating_count int,
  hero_image_url text,
  hero_style text not null default 'warmCocoa'
    check (hero_style in ('warmCocoa','citrus','ocean','meadow')),
  details jsonb not null default '{}'::jsonb,       -- { prepTimeMinutes, cookTimeMinutes, servings }
  nutrition jsonb,                                   -- { calories, protein, carbs, fat, ... }
  ingredients jsonb not null default '[]'::jsonb,    -- [{ section, name, quantity, unit, order }, ...]
  steps jsonb not null default '[]'::jsonb,          -- [{ section, order, text }, ...]
  notes text,
  is_favorite boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists recipes_user_id_idx on public.recipes(user_id);
create index if not exists recipes_book_id_idx on public.recipes(book_id);
create index if not exists recipes_user_favorite_idx on public.recipes(user_id) where is_favorite = true;

-- ============================================================================
-- meal_plan_entries — one entry per (day, meal)
-- ============================================================================
create table if not exists public.meal_plan_entries (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recipe_id uuid not null references public.recipes(id) on delete cascade,
  day_date date not null,
  meal_kind text check (meal_kind in ('breakfast','lunch','dinner')),
  created_at timestamptz not null default now()
);

create index if not exists meal_plan_entries_user_day_idx on public.meal_plan_entries(user_id, day_date);

-- ============================================================================
-- shopping_items — grocery list
-- ============================================================================
create table if not exists public.shopping_items (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_recipe_id uuid references public.recipes(id) on delete set null,
  name text not null,
  quantity text,
  unit text,
  checked boolean not null default false,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists shopping_items_user_id_idx on public.shopping_items(user_id);

-- ============================================================================
-- updated_at auto-touch trigger
-- ============================================================================
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists recipe_books_touch on public.recipe_books;
create trigger recipe_books_touch before update on public.recipe_books
  for each row execute function public.touch_updated_at();

drop trigger if exists recipes_touch on public.recipes;
create trigger recipes_touch before update on public.recipes
  for each row execute function public.touch_updated_at();

-- ============================================================================
-- Row Level Security — every user sees/modifies only their own rows
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.recipe_books enable row level security;
alter table public.recipes enable row level security;
alter table public.meal_plan_entries enable row level security;
alter table public.shopping_items enable row level security;

-- profiles: row id matches auth user id
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- recipe_books
drop policy if exists "recipe_books_all_own" on public.recipe_books;
create policy "recipe_books_all_own" on public.recipe_books
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- recipes
drop policy if exists "recipes_all_own" on public.recipes;
create policy "recipes_all_own" on public.recipes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- meal_plan_entries
drop policy if exists "meal_plan_all_own" on public.meal_plan_entries;
create policy "meal_plan_all_own" on public.meal_plan_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- shopping_items
drop policy if exists "shopping_items_all_own" on public.shopping_items;
create policy "shopping_items_all_own" on public.shopping_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================================
-- Storage bucket: recipe-images (public read, owner-only write)
-- Convention: file paths are prefixed with the user UUID, e.g.
--   <user-uuid>/<recipe-uuid>.jpg
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('recipe-images', 'recipe-images', true, 10485760)
on conflict (id) do nothing;

drop policy if exists "recipe_images_public_read" on storage.objects;
create policy "recipe_images_public_read" on storage.objects
  for select using (bucket_id = 'recipe-images');

drop policy if exists "recipe_images_insert_own" on storage.objects;
create policy "recipe_images_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "recipe_images_update_own" on storage.objects;
create policy "recipe_images_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "recipe_images_delete_own" on storage.objects;
create policy "recipe_images_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
