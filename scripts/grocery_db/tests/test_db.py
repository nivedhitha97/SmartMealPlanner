import dataclasses
import datetime as dt
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from grocery_db import __main__ as cli
from grocery_db import dates, export
from grocery_db.db import Database, utc
from grocery_db.records import Offer, Product
from grocery_db.stores import STORES


def at(text):
    return dt.datetime.fromisoformat(text).replace(tzinfo=dates.AMSTERDAM)


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.db = Database(Path(self.folder.name) / "grocery.db")
        self.db.sync_stores(STORES)

    def tearDown(self):
        self.db.connection.close()
        self.folder.cleanup()

    def test_price_history_records_only_changes(self):
        products = [Product("a", "Kaas", 3.0), Product("b", "Melk", 1.0)]
        self.assertEqual(self.db.save_catalog("spar", products, "2026-10-05T04:00:00Z"), (2, 0))
        self.assertEqual(self.db.save_catalog("spar", products, "2026-10-12T04:00:00Z"), (2, 0))
        products[0].price = 2.5
        self.assertEqual(self.db.save_catalog("spar", products, "2026-10-19T04:00:00Z"), (2, 1))
        history = self.db.connection.execute("SELECT product_key, price FROM price_history ORDER BY rowid").fetchall()
        self.assertEqual([tuple(r) for r in history], [("a", 3.0), ("b", 1.0), ("a", 2.5)])
        row = self.db.connection.execute("SELECT price, price_since FROM products WHERE product_key = 'a'").fetchone()
        self.assertEqual(tuple(row), (2.5, "2026-10-19T04:00:00Z"))

    def test_offers_are_stored_once_and_counted_as_new_once(self):
        offer = Offer("1", "Hak", "2026-10-14T00:00:00+02:00", "2026-10-20T23:59:59+02:00", 2.0)
        self.assertEqual(self.db.save_offers("hoogvliet", [offer], "2026-10-14T04:00:00Z"), 1)
        self.assertEqual(self.db.save_offers("hoogvliet", [offer], "2026-10-15T04:00:00Z"), 0)
        stored = self.db.connection.execute("SELECT valid_from, valid_to FROM offers").fetchone()
        self.assertEqual(tuple(stored), ("2026-10-13T22:00:00Z", "2026-10-20T21:59:59Z"), "stored in UTC")

    def test_current_offers_are_valid_now_or_starting_within_a_day(self):
        make = lambda key, start, end: Offer(key, key, start, end, 1.0)
        self.db.save_offers("dirk", [
            make("ended", "2026-10-07T00:00:00+02:00", "2026-10-13T23:59:59+02:00"),
            make("now", "2026-10-14T00:00:00+02:00", "2026-10-20T23:59:59+02:00"),
            make("tomorrow", "2026-10-16T00:00:00+02:00", "2026-10-18T23:59:59+02:00"),
            make("next-week", "2026-10-21T00:00:00+02:00", "2026-10-27T23:59:59+02:00"),
        ], "2026-10-14T04:00:00Z")
        keys = [r["offer_key"] for r in self.db.current_offers(at("2026-10-15 12:00"))]
        self.assertEqual(keys, ["now", "tomorrow"])


class UpdateTests(unittest.TestCase):
    """The weekly schedule end to end, with the network replaced by fakes."""

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.db = Database(Path(self.folder.name) / "grocery.db")
        self.db.sync_stores(STORES)
        self.calls = []
        self.unexpected = []

    def tearDown(self):
        self.assertEqual(self.unexpected, [], "stores fetched although not due")
        self.db.connection.close()
        self.folder.cleanup()

    def fake_offers(self, store_id, start):
        def fetch(http):
            self.calls.append(store_id)
            http.requests += 1
            day = dt.date.fromisoformat(start)
            return [Offer(f"{store_id}-{i}", "Kipfilet", dates.local_start(day),
                          dates.local_end(day + dt.timedelta(days=6)), 2.0, 3.0) for i in range(12)]
        return fetch

    def run_update(self, now, starts):
        """Runs an update where the stores in `starts` publish offers starting that day; fetching any other
        store's offers fails the test (see tearDown)."""
        patched = {
            store.id: dataclasses.replace(store, fetch_offers=self.fake_offers(store.id, starts[store.id])
                                          if store.id in starts else self.not_due(store.id))
            if store.fetch_offers else store
            for store in STORES
        }

        def catalog(http):
            http.requests += 1
            return {store_id: [Product("p", "Kipfilet 500 g", 5.0, "500 g")] for store_id in patched}

        with mock.patch.dict(cli.BY_ID, patched), \
             mock.patch.object(cli.checkjebon, "fetch_catalogs", catalog), \
             mock.patch.object(cli.checkjebon, "fetch_catalogs_at", lambda *a, **k: None):
            return cli.update(self.db, now)

    def not_due(self, store_id):
        def fetch(http):
            self.unexpected.append(store_id)
            return []
        return fetch

    def test_first_run_fetches_every_store_then_nothing_until_an_update_day(self):
        starts = {"jumbo": "2026-10-14", "lidl": "2026-10-12", "dirk": "2026-10-14", "dekamarkt": "2026-10-13",
                  "hoogvliet": "2026-10-14", "poiesz": "2026-10-11"}
        requests = self.run_update(at("2026-10-15 07:00"), starts)
        self.assertEqual(sorted(self.calls), sorted(starts))
        self.assertEqual(requests, len(starts) + 1, "one request per store plus one shared catalog download")

        self.calls.clear()
        self.assertIsNone(self.run_update(at("2026-10-15 18:00"), starts), "same day: nothing due")
        self.assertIsNone(self.run_update(at("2026-10-17 07:00"), starts), "Saturday: nothing due")
        self.assertEqual(self.calls, [])

    def test_on_an_update_day_only_that_store_is_fetched(self):
        starts = {"jumbo": "2026-10-14", "lidl": "2026-10-12", "dirk": "2026-10-14", "dekamarkt": "2026-10-13",
                  "hoogvliet": "2026-10-14", "poiesz": "2026-10-11"}
        self.run_update(at("2026-10-15 07:00"), starts)
        self.calls.clear()

        requests = self.run_update(at("2026-10-18 07:00"), {"poiesz": "2026-10-18"})  # Sunday
        self.assertEqual(self.calls, ["poiesz"])
        self.assertEqual(requests, 2, "Poiesz plus the shared catalog download")
        self.assertEqual(self.db.store("poiesz")["fetched_week"], "2026-10-18")

    def test_store_that_has_not_published_is_retried_next_morning(self):
        starts = {"jumbo": "2026-10-14", "lidl": "2026-10-12", "dirk": "2026-10-14", "dekamarkt": "2026-10-13",
                  "hoogvliet": "2026-10-14", "poiesz": "2026-10-11"}
        self.run_update(at("2026-10-15 07:00"), starts)
        self.calls.clear()

        # Monday: Lidl still shows last week's offers; Poiesz's Sunday update is caught up.
        self.run_update(at("2026-10-19 07:00"), {"lidl": "2026-10-12", "poiesz": "2026-10-18"})
        self.assertEqual(sorted(self.calls), ["lidl", "poiesz"])
        self.assertEqual(self.db.store("lidl")["fetched_week"], "2026-10-12", "new week not published yet")
        self.calls.clear()
        self.run_update(at("2026-10-20 07:00"), {"lidl": "2026-10-19", "dekamarkt": "2026-10-20"})  # Tuesday
        self.assertEqual(sorted(self.calls), ["dekamarkt", "lidl"])
        self.assertEqual(self.db.store("lidl")["fetched_week"], "2026-10-19")

    def test_export_writes_the_app_files_with_the_schedule(self):
        starts = {"jumbo": "2026-10-14", "lidl": "2026-10-12", "dirk": "2026-10-14", "dekamarkt": "2026-10-13",
                  "hoogvliet": "2026-10-14", "poiesz": "2026-10-11"}
        now = at("2026-10-15 07:00")
        requests = self.run_update(now, starts)
        meta = export.export(self.db, now, Path(self.folder.name), requests)
        self.assertEqual(meta["requests"]["thisRun"], requests)
        self.assertEqual(meta["nextUpdateAt"], utc(at("2026-10-18 06:00")), "Poiesz on Sunday is next")
        poiesz = next(s for s in meta["stores"] if s["id"] == "poiesz")
        self.assertEqual((poiesz["updateDay"], poiesz["fetchesOffers"]), ("Sunday", True))
        for name in ("offers.json", "prices.json", "meta.json"):
            self.assertTrue((Path(self.folder.name) / name).exists())


if __name__ == "__main__":
    unittest.main()
