-- SmartMealPlanner grocery database: tables for the Supabase mirror.
-- Run once in Supabase → SQL Editor → New query. Safe to run again.
--
-- The weekly update (scripts/grocery_db) writes everything except the columns marked EDITABLE. Edit those in the
-- Table Editor; the next morning's run copies them into the app's data, and later fetches never overwrite them.

create table if not exists stores (
    id text primary key,
    name text not null,
    update_weekday smallint not null check (update_weekday between 0 and 6),  -- 0 = Monday
    update_day text generated always as ((array['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])[update_weekday + 1]) stored,
    weekday_source text not null,
    weekday_note text,
    has_offers boolean not null,
    has_catalog boolean not null,
    last_success_at timestamptz,
    last_error text,
    catalog_changed_at timestamptz,
    manual_update_weekday smallint check (manual_update_weekday between 0 and 6)  -- EDITABLE: fetch on this day instead
);

create table if not exists products (
    store_id text not null references stores(id),
    product_key text not null,
    name text not null,
    size text,
    url text,
    price numeric(10, 2) not null,             -- shelf price from the latest fetch
    price_since timestamptz,
    first_seen timestamptz,
    price_override numeric(10, 2),             -- EDITABLE: use this price instead
    override_note text,                        -- EDITABLE: why
    effective_price numeric(10, 2) generated always as (coalesce(price_override, price)) stored,
    primary key (store_id, product_key)
);
create index if not exists products_name on products using gin (to_tsvector('dutch', name));

create table if not exists price_history (
    store_id text not null,
    product_key text not null,
    price numeric(10, 2) not null,
    observed_at timestamptz not null,
    primary key (store_id, product_key, observed_at)
);

create table if not exists offers (
    store_id text not null references stores(id),
    offer_key text not null,
    valid_from timestamptz not null,
    valid_to timestamptz not null,
    title text not null,
    size text,
    deal_text text,
    offer_price numeric(10, 2),
    regular_price numeric(10, 2),
    category text,
    url text,
    first_seen timestamptz,
    offer_price_override numeric(10, 2),       -- EDITABLE: use this price instead
    hidden boolean not null default false,     -- EDITABLE: leave this offer out of the app
    override_note text,                        -- EDITABLE: why
    primary key (store_id, offer_key, valid_from)
);

create table if not exists fetch_log (
    id bigint primary key,
    store_id text,
    kind text not null,
    started_at timestamptz not null,
    finished_at timestamptz not null,
    status text not null,
    items integer not null default 0,
    requests integer not null default 0,
    message text
);

-- Handy views for browsing.
create or replace view offers_this_week as
    select s.name as store, o.title, o.deal_text, coalesce(o.offer_price_override, o.offer_price) as price,
           o.regular_price, o.size, o.valid_from, o.valid_to, o.hidden, o.store_id, o.offer_key
    from offers o join stores s on s.id = o.store_id
    where o.valid_to >= now() and o.valid_from <= now() + interval '1 day'
    order by s.name, o.title;

create or replace view requests_per_week as
    select date_trunc('week', started_at) as week, store_id, sum(requests) as requests, count(*) as fetches
    from fetch_log group by 1, 2 order by 1 desc, 2;

-- Only you (in the dashboard) and the update job (with the service_role key) can read or change the data:
-- row level security is on and no policies are granted to the public anon key.
alter table stores enable row level security;
alter table products enable row level security;
alter table price_history enable row level security;
alter table offers enable row level security;
alter table fetch_log enable row level security;
alter view offers_this_week set (security_invoker = true);
alter view requests_per_week set (security_invoker = true);
