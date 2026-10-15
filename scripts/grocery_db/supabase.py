"""Mirror of the grocery database in Supabase (hosted Postgres), so it can be browsed and edited in Supabase's
table editor.

After every update, rows that are new or changed since the last sync are upserted (never the EDITABLE columns
in supabase_schema.sql). Before every export, the manual edits are read back and applied. Uses Supabase's REST
API (PostgREST) with the service_role key from the SUPABASE_SERVICE_KEY environment variable; the key is never
logged or published.
"""

import json
import os
import urllib.parse

from .db import utc
from .web import FetchError, Http

BATCH = 1000
# Supabase refuses secret keys from anything that looks like a web browser, so this job doesn't pretend to be one
# (unlike the store fetchers).
USER_AGENT = "SmartMealPlanner-grocery-db/1.0 (+https://github.com/nivedhitha97/SmartMealPlanner)"


class Supabase:
    def __init__(self, url, key, http=None):
        self.base = url.rstrip("/") + "/rest/v1/"
        self.key = key
        self.http = http or Http(pause=0.1, user_agent=USER_AGENT)

    @classmethod
    def from_environment(cls):
        """A client if SUPABASE_URL and SUPABASE_SERVICE_KEY are set, else None."""
        url, key = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_KEY")
        return cls(url, key) if url and key else None

    def _headers(self, **extra):
        headers = {"apikey": self.key, **extra}
        if self.key.startswith("eyJ"):  # legacy service_role JWT; new sb_secret_ keys go in `apikey` only
            headers["Authorization"] = f"Bearer {self.key}"
        return headers

    def upsert(self, table, rows, conflict):
        """Inserts or updates `rows` (dicts) in batches; only the columns given are written."""
        for start in range(0, len(rows), BATCH):
            self.http.get(f"{self.base}{table}?on_conflict={conflict}", data=rows[start:start + BATCH],
                          headers=self._headers(Prefer="resolution=merge-duplicates,return=minimal"))
        return len(rows)

    def select(self, table, columns, filters=""):
        """All matching rows, paged."""
        rows, offset = [], 0
        while True:
            query = f"select={columns}&limit={BATCH}&offset={offset}" + (f"&{filters}" if filters else "")
            page = json.loads(self.http.get(f"{self.base}{table}?{query}", headers=self._headers()))
            rows.extend(page)
            if len(page) < BATCH:
                return rows
            offset += BATCH


def push(db, supabase, full=False):
    """Sends rows new or changed since the last sync (everything with `full`). Returns rows sent per table."""
    since = None if full else db.sync_value("pushed_at")
    started = db.connection.execute("SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')").fetchone()[0]
    after = lambda column: (f" WHERE {column} >= ?", (since,)) if since else ("", ())

    def rows(sql, params=()):
        return [dict(r) for r in db.connection.execute(sql, params)]

    sent = {}
    sent["stores"] = supabase.upsert("stores", [
        {**r, "has_offers": bool(r["has_offers"]), "has_catalog": bool(r["has_catalog"])}
        for r in rows("""SELECT id, name, update_weekday, weekday_source, weekday_note, has_offers, has_catalog,
                                last_success_at, last_error, catalog_changed_at FROM stores""")], "id")
    where, params = (" WHERE price_since >= ? OR first_seen >= ?", (since, since)) if since else ("", ())
    sent["products"] = supabase.upsert("products", rows(
        "SELECT store_id, product_key, name, size, url, price, price_since, first_seen FROM products" + where, params),
        "store_id,product_key")
    where, params = after("observed_at")
    sent["price_history"] = supabase.upsert("price_history", rows(
        "SELECT store_id, product_key, price, observed_at FROM price_history" + where, params),
        "store_id,product_key,observed_at")
    where, params = after("last_seen")
    sent["offers"] = supabase.upsert("offers", rows(
        """SELECT store_id, offer_key, valid_from, valid_to, title, size, deal_text, offer_price, regular_price,
                  category, url, first_seen FROM offers""" + where, params), "store_id,offer_key,valid_from")
    where, params = after("started_at")
    sent["fetch_log"] = supabase.upsert("fetch_log", rows(
        "SELECT id, store_id, kind, started_at, finished_at, status, items, requests, message FROM fetch_log" + where,
        params), "id")
    db.set_sync_value("pushed_at", started)
    return sent


def pull_overrides(db, supabase):
    """Reads the manual edits from Supabase and applies them. Returns True if they changed."""
    products = supabase.select("products", "store_id,product_key,price_override,override_note",
                               "price_override=not.is.null")
    offers = supabase.select("offers", "store_id,offer_key,valid_from,offer_price_override,hidden,override_note",
                             "or=" + urllib.parse.quote("(offer_price_override.not.is.null,hidden.is.true)"))
    stores = supabase.select("stores", "id,manual_update_weekday", "manual_update_weekday=not.is.null")
    overrides = {
        "products": sorted((r["store_id"], r["product_key"], float(r["price_override"]), r["override_note"])
                           for r in products),
        "offers": sorted((r["store_id"], r["offer_key"], utc(r["valid_from"]),
                          float(r["offer_price_override"]) if r["offer_price_override"] is not None else None,
                          int(bool(r["hidden"])), r["override_note"]) for r in offers),
        "stores": sorted((r["id"], int(r["manual_update_weekday"])) for r in stores),
    }
    if overrides == db.overrides():
        return False
    db.replace_overrides(overrides)
    return True


__all__ = ["Supabase", "push", "pull_overrides", "FetchError"]
