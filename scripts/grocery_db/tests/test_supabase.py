"""The Supabase mirror: pushing changes, and manual edits flowing back into the app's data and the schedule."""

import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path

from grocery_db import dates, export, schedule, supabase
from grocery_db.db import Database
from grocery_db.records import Offer, Product
from grocery_db.stores import STORES


class FakeSupabase:
    """In-memory tables with PostgREST-style upsert (only the given columns are written)."""

    def __init__(self):
        self.tables = {}
        self.upserts = {}

    def upsert(self, table, rows, conflict):
        keys = conflict.split(",")
        stored = self.tables.setdefault(table, {})
        for row in rows:
            key = tuple(row[k] for k in keys)
            stored[key] = {**stored.get(key, {}), **row}
        self.upserts[table] = self.upserts.get(table, 0) + len(rows)
        return len(rows)

    def edit(self, table, key, **values):
        self.tables[table][key].update(values)

    def select(self, table, columns, filters=""):
        rows = list(self.tables.get(table, {}).values())
        if table == "products":
            rows = [r for r in rows if r.get("price_override") is not None]
        elif table == "offers":
            rows = [r for r in rows if r.get("offer_price_override") is not None or r.get("hidden")]
        elif table == "stores":
            rows = [r for r in rows if r.get("manual_update_weekday") is not None]
        return [{c: r.get(c) for c in columns.split(",")} for r in rows]


def at(text):
    return dt.datetime.fromisoformat(text).replace(tzinfo=dates.AMSTERDAM)


class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.db = Database(Path(self.folder.name) / "grocery.db")
        self.db.sync_stores(STORES)
        self.db.save_catalog("jumbo", [Product("p1", "Jumbo Kipfilet 500 g", 5.99, "500 g"),
                                       Product("p2", "Jumbo Rijst 1 kg", 1.49, "1 kg")], "2026-10-14T04:15:00Z")
        self.db.update_store("jumbo", catalog_changed_at="2026-10-14T04:15:00Z")
        self.db.save_offers("dirk", [Offer("o1", "Hollandse aardbeien", "2026-10-14T00:00:00+02:00",
                                           "2026-10-20T23:59:59+02:00", 2.49, 2.99),
                                     Offer("o2", "Kipfilet", "2026-10-14T00:00:00+02:00",
                                           "2026-10-20T23:59:59+02:00", 4.99, 6.49)], "2026-10-14T04:15:00Z")
        self.mirror = FakeSupabase()

    def tearDown(self):
        self.db.connection.close()
        self.folder.cleanup()

    def test_first_push_sends_everything_then_only_changes(self):
        first = supabase.push(self.db, self.mirror)
        self.assertEqual((first["products"], first["offers"], first["stores"]), (2, 2, len(STORES)))
        self.assertIs(self.mirror.tables["stores"][("jumbo",)]["has_offers"], True, "booleans, not 0/1")

        self.db.set_sync_value("pushed_at", "2026-10-15T00:00:00Z")
        self.db.save_catalog("jumbo", [Product("p1", "Jumbo Kipfilet 500 g", 5.49, "500 g"),
                                       Product("p2", "Jumbo Rijst 1 kg", 1.49, "1 kg")], "2026-10-21T04:15:00Z")
        second = supabase.push(self.db, self.mirror)
        self.assertEqual((second["products"], second["price_history"], second["offers"]), (1, 1, 0),
                         "only the product whose price changed")
        self.assertEqual(self.mirror.tables["products"][("jumbo", "p1")]["price"], 5.49)

    def test_pushing_never_overwrites_manual_edits(self):
        supabase.push(self.db, self.mirror)
        self.mirror.edit("products", ("jumbo", "p1"), price_override=4.00, override_note="checked in store")
        supabase.push(self.db, self.mirror, full=True)
        self.assertEqual(self.mirror.tables["products"][("jumbo", "p1")]["price_override"], 4.00)

    def test_edited_prices_and_hidden_offers_reach_the_export(self):
        supabase.push(self.db, self.mirror)
        self.mirror.edit("products", ("jumbo", "p1"), price_override=4.00)
        offers = self.mirror.tables["offers"]
        offers[next(k for k in offers if k[1] == "o1")]["hidden"] = True
        offers[next(k for k in offers if k[1] == "o2")]["offer_price_override"] = 3.99

        self.assertTrue(supabase.pull_overrides(self.db, self.mirror))
        self.assertFalse(supabase.pull_overrides(self.db, self.mirror), "nothing new the second time")

        now = at("2026-10-15 12:00")
        export.export(self.db, now, Path(self.folder.name), 0)
        exported = json.loads((Path(self.folder.name) / "offers.json").read_text())
        titles = {o["productName"]: o["offerPrice"] for o in exported if o["storeName"] == "Dirk"}
        self.assertEqual(titles, {"Kipfilet": 3.99}, "aardbeien hidden, kipfilet at the edited price")
        prices = json.loads((Path(self.folder.name) / "prices.json").read_text())
        chicken = next(p for p in prices if p["ingredientName"] == "Chicken Breast")
        self.assertEqual(chicken["cheapestPrice"], 4.00)

    def test_removing_an_edit_in_supabase_removes_it_here(self):
        supabase.push(self.db, self.mirror)
        self.mirror.edit("products", ("jumbo", "p1"), price_override=4.00)
        supabase.pull_overrides(self.db, self.mirror)
        self.mirror.edit("products", ("jumbo", "p1"), price_override=None)

        self.assertTrue(supabase.pull_overrides(self.db, self.mirror))
        self.assertEqual([r["price"] for r in self.db.catalog("jumbo") if r["product_key"] == "p1"], [5.99])

    def test_manual_update_day_changes_the_schedule(self):
        supabase.push(self.db, self.mirror)
        self.mirror.edit("stores", ("jumbo",), manual_update_weekday=3)  # Thursday
        supabase.pull_overrides(self.db, self.mirror)

        row = self.db.store("jumbo")
        self.assertEqual(schedule.weekday_of(row), 3)
        meta = export.export(self.db, at("2026-10-15 12:00"), Path(self.folder.name), 0)
        jumbo = next(s for s in meta["stores"] if s["id"] == "jumbo")
        self.assertEqual((jumbo["updateDay"], jumbo["updateDaySource"]), ("Thursday", "manual"))


class RestTests(unittest.TestCase):
    """The REST calls themselves, with the HTTP layer recorded instead of sent."""

    class Recorder:
        def __init__(self, pages=()):
            self.calls, self.pages = [], list(pages)

        def get(self, url, headers=None, data=None):
            self.calls.append((url, headers, data))
            return json.dumps(self.pages.pop(0) if self.pages else []).encode()

    def test_upsert_merges_on_the_key_in_batches_with_the_service_key(self):
        recorder = self.Recorder()
        client = supabase.Supabase("https://abc.supabase.co/", "secret", recorder)
        client.upsert("products", [{"store_id": "a", "product_key": str(i)} for i in range(2500)], "store_id,product_key")

        self.assertEqual(len(recorder.calls), 3)
        url, headers, data = recorder.calls[0]
        self.assertEqual(url, "https://abc.supabase.co/rest/v1/products?on_conflict=store_id,product_key")
        self.assertEqual(headers["apikey"], "secret")
        self.assertIn("merge-duplicates", headers["Prefer"])
        self.assertEqual(len(data), 1000)

    def test_new_secret_keys_go_only_in_the_apikey_header(self):
        recorder = self.Recorder()
        supabase.Supabase("https://abc.supabase.co", "sb_secret_abc", recorder).select("stores", "id")
        headers = recorder.calls[0][1]
        self.assertEqual(headers["apikey"], "sb_secret_abc")
        self.assertNotIn("Authorization", headers)

    def test_legacy_jwt_keys_are_also_sent_as_bearer(self):
        recorder = self.Recorder()
        supabase.Supabase("https://abc.supabase.co", "eyJhbGciOi.x.y", recorder).select("stores", "id")
        self.assertEqual(recorder.calls[0][1]["Authorization"], "Bearer eyJhbGciOi.x.y")

    def test_the_client_does_not_identify_as_a_browser(self):
        client = supabase.Supabase("https://abc.supabase.co", "sb_secret_abc")
        self.assertNotIn("Mozilla", client.http.user_agent)
        self.assertIn("Mozilla", supabase.Http().user_agent, "store fetchers still look like a browser")

    def test_select_pages_until_a_short_page(self):
        recorder = self.Recorder([[{"id": i} for i in range(1000)], [{"id": 1000}]])
        client = supabase.Supabase("https://abc.supabase.co", "secret", recorder)
        rows = client.select("stores", "id", "manual_update_weekday=not.is.null")

        self.assertEqual(len(rows), 1001)
        self.assertIn("offset=1000", recorder.calls[1][0])
        self.assertIn("manual_update_weekday=not.is.null", recorder.calls[0][0])

    def test_no_client_without_both_settings(self):
        import os
        from unittest import mock
        with mock.patch.dict(os.environ, {"SUPABASE_URL": "https://abc.supabase.co"}, clear=True):
            self.assertIsNone(supabase.Supabase.from_environment())


if __name__ == "__main__":
    unittest.main()
