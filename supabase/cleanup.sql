-- One-time clean-up, run in the Supabase SQL editor of the project that hosted recipe search and the grocery mirror.
--
-- 1. Recipe search used Spoonacular, whose terms require deleting all data obtained from its API once it is no longer
--    used. The cache held Spoonacular recipes; the log held hashed caller addresses. Both tables are dropped.
-- 2. The grocery mirror held offers and prices read from supermarket websites and Checkjebon by earlier versions.
--    Everything that didn't come from Open Prices is deleted, with the request log that described those fetches.
--    The next grocery update fills the mirror again with Open Prices data only.

drop table if exists recipe_search_cache;
drop table if exists recipe_search_log;

delete from offers where url is null or url not like 'https://prices.openfoodfacts.org/%';
update offers set image_url = null where image_url is not null;
delete from products where url is null or url not like 'https://prices.openfoodfacts.org/%';
delete from price_history h
  where not exists (select 1 from products p where p.store_id = h.store_id and p.product_key = h.product_key);
delete from fetch_log;
