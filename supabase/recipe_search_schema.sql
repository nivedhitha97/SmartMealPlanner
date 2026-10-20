-- Tables for the recipe-search Edge Function (supabase/functions/recipe-search). Run once in the Supabase SQL editor.
-- Only the function (service role) uses them: row level security is on with no policies, so the app's keys can't
-- read or write them.

create table if not exists recipe_search_cache (
  key text primary key,                 -- SHA-256 of diet, cuisines, allergies and dislikes
  recipes jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists recipe_search_log (  -- one row per new (uncached) search, for the daily limits
  id bigint generated always as identity primary key,
  caller text not null,                 -- SHA-256 of the caller's IP address, never the address itself
  created_at timestamptz not null default now()
);
create index if not exists recipe_search_log_created_at on recipe_search_log (created_at);

alter table recipe_search_cache enable row level security;
alter table recipe_search_log enable row level security;
