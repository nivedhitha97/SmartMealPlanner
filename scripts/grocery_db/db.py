"""The SQLite database: stores and their schedule, catalog products with price history, offers, and a log of
every fetch (with its request count)."""

import datetime as dt
import sqlite3

from . import dates

SCHEMA = """
CREATE TABLE IF NOT EXISTS stores (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    update_weekday INTEGER NOT NULL,      -- 0 = Monday; the day the store starts its offer week
    weekday_source TEXT NOT NULL,         -- 'configured' or 'learned' (from offer start dates)
    weekday_note TEXT,
    has_offers INTEGER NOT NULL,          -- fetched from the store itself
    has_catalog INTEGER NOT NULL,         -- has shelf prices (from Open Prices)
    fetched_week TEXT,                    -- start date of the last offer week fetched
    attempts_week TEXT,                   -- offer week the attempt counter belongs to
    attempts INTEGER NOT NULL DEFAULT 0,
    last_fetch_at TEXT,
    last_success_at TEXT,
    last_error TEXT,
    catalog_changed_at TEXT               -- last time any of the store's shelf prices changed
);

CREATE TABLE IF NOT EXISTS products (
    store_id TEXT NOT NULL REFERENCES stores(id),
    product_key TEXT NOT NULL,
    name TEXT NOT NULL,
    size TEXT,
    url TEXT,
    price REAL NOT NULL,                  -- current shelf price
    price_since TEXT NOT NULL,
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    PRIMARY KEY (store_id, product_key)
);

CREATE TABLE IF NOT EXISTS price_history (    -- one row per price change
    store_id TEXT NOT NULL,
    product_key TEXT NOT NULL,
    price REAL NOT NULL,
    observed_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS price_history_product ON price_history (store_id, product_key, observed_at);

CREATE TABLE IF NOT EXISTS offers (
    store_id TEXT NOT NULL REFERENCES stores(id),
    offer_key TEXT NOT NULL,
    valid_from TEXT NOT NULL,
    valid_to TEXT NOT NULL,
    title TEXT NOT NULL,
    size TEXT,
    deal_text TEXT,
    offer_price REAL,
    regular_price REAL,
    category TEXT,
    url TEXT,
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    PRIMARY KEY (store_id, offer_key, valid_from)
);
CREATE INDEX IF NOT EXISTS offers_valid ON offers (valid_to);

CREATE TABLE IF NOT EXISTS sync_state (     -- bookkeeping for the Supabase mirror
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS fetch_log (
    id INTEGER PRIMARY KEY,
    store_id TEXT,                        -- NULL for requests not tied to one store
    kind TEXT NOT NULL,                   -- 'offers', 'catalog' or 'catalog-baseline'
    started_at TEXT NOT NULL,
    finished_at TEXT NOT NULL,
    status TEXT NOT NULL,                 -- 'ok', 'no-new-week' or 'error'
    items INTEGER NOT NULL DEFAULT 0,
    requests INTEGER NOT NULL DEFAULT 0,
    message TEXT
);
"""


# Columns added after the first release, as migrations so existing databases get them too. The override columns
# hold manual edits made in the Supabase table editor, copied in before every export.
ADDED_COLUMNS = {
    "products": [("price_override", "REAL"), ("override_note", "TEXT")],
    "offers": [("image_url", "TEXT"),
               ("offer_price_override", "REAL"), ("hidden", "INTEGER NOT NULL DEFAULT 0"), ("override_note", "TEXT")],
    "stores": [("manual_update_weekday", "INTEGER")],
}


class Database:
    def __init__(self, path):
        self.connection = sqlite3.connect(path)
        self.connection.row_factory = sqlite3.Row
        self.connection.executescript(SCHEMA)
        for table, columns in ADDED_COLUMNS.items():
            existing = {row["name"] for row in self.connection.execute(f"PRAGMA table_info({table})")}
            for name, kind in columns:
                if name not in existing:
                    self.connection.execute(f"ALTER TABLE {table} ADD COLUMN {name} {kind}")
        self.connection.commit()

    def close(self):
        self.connection.commit()
        self.connection.execute("VACUUM")
        self.connection.close()

    # ---- Only open data ----

    OPEN_DATA_URL = "https://prices.openfoodfacts.org/%"

    def remove_data_not_from_open_prices(self):
        """Deletes every offer, product and price that didn't come from Open Prices (data read from supermarket
        websites or Checkjebon by earlier versions), and every product photo. Returns how many rows went."""
        removed = 0
        for table in ("offers", "products"):
            removed += self.connection.execute(
                f"DELETE FROM {table} WHERE url IS NULL OR url NOT LIKE ?", (self.OPEN_DATA_URL,)).rowcount
        removed += self.connection.execute(
            """DELETE FROM price_history WHERE NOT EXISTS (SELECT 1 FROM products p WHERE
                   p.store_id = price_history.store_id AND p.product_key = price_history.product_key)""").rowcount
        self.connection.execute("UPDATE offers SET image_url = NULL WHERE image_url IS NOT NULL")
        if removed:
            self.connection.execute("DELETE FROM fetch_log")  # the old log describes requests to store websites
            self.connection.execute("UPDATE stores SET catalog_changed_at = NULL, fetched_week = NULL, "
                                    "attempts_week = NULL, attempts = 0, last_error = NULL")
        self.connection.commit()
        return removed

    # ---- Stores ----

    def sync_stores(self, stores):
        """Adds new stores and refreshes names and sources; keeps learned weekdays and fetch state."""
        for store in stores:
            self.connection.execute(
                """INSERT INTO stores (id, name, update_weekday, weekday_source, weekday_note, has_offers, has_catalog)
                   VALUES (?, ?, ?, 'configured', ?, ?, ?)
                   ON CONFLICT(id) DO UPDATE SET name = excluded.name, has_offers = excluded.has_offers,
                       has_catalog = excluded.has_catalog,
                       weekday_note = CASE WHEN stores.weekday_source = 'configured'
                                           THEN excluded.weekday_note ELSE stores.weekday_note END""",
                (store.id, store.name, store.update_weekday, store.weekday_note, 1, 1))
        self.connection.commit()

    def store(self, store_id):
        return self.connection.execute("SELECT * FROM stores WHERE id = ?", (store_id,)).fetchone()

    def stores(self):
        return self.connection.execute("SELECT * FROM stores ORDER BY name").fetchall()

    def update_store(self, store_id, **fields):
        assignments = ", ".join(f"{name} = ?" for name in fields)
        self.connection.execute(f"UPDATE stores SET {assignments} WHERE id = ?", (*fields.values(), store_id))
        self.connection.commit()

    # ---- Offers ----

    def save_offers(self, store_id, offers, now):
        """Inserts new offers and refreshes ones already stored. Returns how many were new."""
        new = 0
        for offer in offers:
            cursor = self.connection.execute(
                """INSERT INTO offers (store_id, offer_key, valid_from, valid_to, title, size, deal_text, offer_price,
                                       regular_price, category, url, image_url, first_seen, last_seen)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                   ON CONFLICT(store_id, offer_key, valid_from) DO UPDATE SET
                       valid_to = excluded.valid_to, title = excluded.title, size = excluded.size,
                       deal_text = excluded.deal_text, offer_price = excluded.offer_price,
                       regular_price = excluded.regular_price, category = excluded.category, url = excluded.url,
                       image_url = coalesce(excluded.image_url, offers.image_url), last_seen = excluded.last_seen
                   RETURNING first_seen = last_seen""",
                (store_id, offer.key, utc(offer.valid_from), utc(offer.valid_to), offer.title, offer.size, offer.deal_text,
                 offer.offer_price, offer.regular_price, offer.category, offer.url, offer.image_url, now, now))
            new += int(bool(cursor.fetchone()[0]))
        self.connection.commit()
        return new

    def current_offers(self, now):
        """Offers valid at `now` or starting within a day, with manual edits applied (hidden offers left out,
        overridden prices used)."""
        return self.connection.execute(
            """SELECT store_id, offer_key, valid_from, valid_to, title, size, deal_text, regular_price, category,
                      url, image_url, coalesce(offer_price_override, offer_price) AS offer_price
               FROM offers WHERE valid_to >= ? AND valid_from <= ? AND hidden = 0
               ORDER BY store_id, offer_key""",
            (utc(now), utc(now + dt.timedelta(days=1)))).fetchall()

    # ---- Catalog ----

    def save_catalog(self, store_id, products, now):
        """Updates the store's products; records a price_history row for every new or changed price.
        Returns (products, changed prices)."""
        current = {row["product_key"]: row["price"] for row in self.connection.execute(
            "SELECT product_key, price FROM products WHERE store_id = ?", (store_id,))}
        changed = 0
        history = []
        rows = []
        for product in products:
            old = current.get(product.key)
            if old is None or abs(old - product.price) > 0.001:
                history.append((store_id, product.key, product.price, now))
                changed += old is not None
            rows.append((store_id, product.key, product.name, product.size, product.url, product.price, now, now, now))
        self.connection.executemany(
            """INSERT INTO products (store_id, product_key, name, size, url, price, price_since, first_seen, last_seen)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(store_id, product_key) DO UPDATE SET
                   name = excluded.name, size = excluded.size, url = excluded.url, last_seen = excluded.last_seen,
                   price_since = CASE WHEN abs(products.price - excluded.price) > 0.001
                                      THEN excluded.price_since ELSE products.price_since END,
                   price = excluded.price""", rows)
        self.connection.executemany(
            "INSERT INTO price_history (store_id, product_key, price, observed_at) VALUES (?, ?, ?, ?)", history)
        self.connection.commit()
        return len(products), changed

    def catalog(self, store_id):
        """The store's products in its latest catalog, with manual price edits applied."""
        return self.connection.execute(
            """SELECT store_id, product_key, name, size, url, price_since,
                      coalesce(price_override, price) AS price
               FROM products WHERE store_id = ?
                 AND last_seen = (SELECT max(last_seen) FROM products WHERE store_id = ?)""",
            (store_id, store_id)).fetchall()

    # ---- Manual overrides (from Supabase) ----

    def overrides(self):
        """The manual edits currently applied, in a comparable form."""
        return {
            "products": sorted(tuple(r) for r in self.connection.execute(
                "SELECT store_id, product_key, price_override, override_note FROM products WHERE price_override IS NOT NULL")),
            "offers": sorted(tuple(r) for r in self.connection.execute(
                """SELECT store_id, offer_key, valid_from, offer_price_override, hidden, override_note FROM offers
                   WHERE offer_price_override IS NOT NULL OR hidden = 1""")),
            "stores": sorted(tuple(r) for r in self.connection.execute(
                "SELECT id, manual_update_weekday FROM stores WHERE manual_update_weekday IS NOT NULL")),
        }

    def replace_overrides(self, overrides):
        """Clears all manual edits and applies `overrides` (the shape `overrides()` returns), so an edit removed
        in Supabase is removed here too."""
        c = self.connection
        c.execute("UPDATE products SET price_override = NULL, override_note = NULL WHERE price_override IS NOT NULL")
        c.execute("""UPDATE offers SET offer_price_override = NULL, hidden = 0, override_note = NULL
                     WHERE offer_price_override IS NOT NULL OR hidden = 1""")
        c.execute("UPDATE stores SET manual_update_weekday = NULL")
        c.executemany("""UPDATE products SET price_override = ?, override_note = ?
                         WHERE store_id = ? AND product_key = ?""",
                      [(price, note, store, key) for store, key, price, note in overrides["products"]])
        c.executemany("""UPDATE offers SET offer_price_override = ?, hidden = ?, override_note = ?
                         WHERE store_id = ? AND offer_key = ? AND valid_from = ?""",
                      [(price, int(bool(hidden)), note, store, key, start)
                       for store, key, start, price, hidden, note in overrides["offers"]])
        c.executemany("UPDATE stores SET manual_update_weekday = ? WHERE id = ?",
                      [(day, store) for store, day in overrides["stores"]])
        c.commit()

    # ---- Sync bookkeeping ----

    def sync_value(self, key):
        row = self.connection.execute("SELECT value FROM sync_state WHERE key = ?", (key,)).fetchone()
        return row[0] if row else None

    def set_sync_value(self, key, value):
        self.connection.execute("INSERT INTO sync_state (key, value) VALUES (?, ?) "
                                "ON CONFLICT(key) DO UPDATE SET value = excluded.value", (key, value))
        self.connection.commit()

    def has_catalog(self, store_id):
        return self.connection.execute("SELECT 1 FROM products WHERE store_id = ? LIMIT 1", (store_id,)).fetchone() is not None

    def highest_recent_price(self, store_id, product_key, since):
        row = self.connection.execute(
            """SELECT max(price) FROM price_history WHERE store_id = ? AND product_key = ? AND observed_at >= ?""",
            (store_id, product_key, since)).fetchone()
        return row[0]

    # ---- Log ----

    def log_fetch(self, store_id, kind, started, finished, status, items=0, requests=0, message=None):
        self.connection.execute(
            """INSERT INTO fetch_log (store_id, kind, started_at, finished_at, status, items, requests, message)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (store_id, kind, started, finished, status, items, requests, message))
        self.connection.commit()

    def requests_since(self, since):
        row = self.connection.execute("SELECT coalesce(sum(requests), 0) FROM fetch_log WHERE started_at >= ?",
                                      (since,)).fetchone()
        return row[0]



def utc(value):
    """A timestamp (aware datetime or ISO 8601 string) as UTC 'YYYY-MM-DDTHH:MM:SSZ', so stored times sort
    and compare correctly as text."""
    moment = dates.parse(value) if isinstance(value, str) else value
    return moment.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
