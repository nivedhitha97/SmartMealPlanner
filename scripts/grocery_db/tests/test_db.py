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

    def test_offer_image_is_kept_when_a_later_fetch_has_none(self):
        offer = Offer("1", "Hak", "2026-10-14T00:00:00+02:00", "2026-10-20T23:59:59+02:00", 2.0,
                      image_url="https://example.org/1.jpg")
        self.db.save_offers("hoogvliet", [offer], "2026-10-14T04:00:00Z")
        offer.image_url = None
        self.db.save_offers("hoogvliet", [offer], "2026-10-15T04:00:00Z")
        [row] = self.db.current_offers(at("2026-10-15 12:00"))
        self.assertEqual(row["image_url"], "https://example.org/1.jpg")

    def test_existing_database_gets_the_image_column(self):
        path = Path(self.folder.name) / "old.db"
        import sqlite3
        old = sqlite3.connect(path)
        old.executescript("CREATE TABLE offers (store_id TEXT, offer_key TEXT, valid_from TEXT, valid_to TEXT,"
                          " title TEXT, size TEXT, deal_text TEXT, offer_price REAL, regular_price REAL,"
                          " category TEXT, url TEXT, first_seen TEXT, last_seen TEXT,"
                          " PRIMARY KEY (store_id, offer_key, valid_from));")
        old.close()
        migrated = Database(path)
        columns = {r["name"] for r in migrated.connection.execute("PRAGMA table_info(offers)")}
        migrated.connection.close()
        self.assertIn("image_url", columns)

    def test_data_not_from_open_prices_is_removed(self):
        open_prices = "https://prices.openfoodfacts.org/prices/1"
        self.db.save_catalog("jumbo", [Product("old", "Kaas", 3.0, url="https://www.jumbo.com/kaas"),
                                       Product("new", "Melk", 1.0, url=open_prices)], "2026-10-05T04:00:00Z")
        self.db.save_offers("jumbo", [
            Offer("site", "Hak", "2026-10-14T00:00:00+02:00", "2026-10-20T23:59:59+02:00", 2.0,
                  url="https://www.jumbo.com/hak", image_url="https://static.jumbo.com/hak.jpg"),
            Offer("op", "Kip", "2026-10-14T00:00:00+02:00", "2026-10-20T23:59:59+02:00", 2.0, url=open_prices,
                  image_url="https://images.openfoodfacts.org/kip.jpg"),
        ], "2026-10-14T04:00:00Z")

        self.assertEqual(self.db.remove_data_not_from_open_prices(), 3, "a product, its price history and an offer")
        self.assertEqual([r["product_key"] for r in self.db.catalog("jumbo")], ["new"])
        [offer] = self.db.current_offers(at("2026-10-15 12:00"))
        self.assertEqual((offer["offer_key"], offer["image_url"]), ("op", None), "no product photos")
        self.assertEqual(self.db.remove_data_not_from_open_prices(), 0, "nothing left to remove")

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
    """The daily Open Prices update end to end, with the network replaced by a fake."""

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.db = Database(Path(self.folder.name) / "grocery.db")
        self.db.sync_stores(STORES)
        self.calls = []

    def tearDown(self):
        self.db.connection.close()
        self.folder.cleanup()

    def fake_fetch(self, http, chain, today=None):
        self.calls.append(chain)
        http.requests += 2
        monday = today - dt.timedelta(days=today.weekday())
        offers = [Offer(f"{chain}-1", "Kipfilet", dates.local_start(monday),
                        dates.local_end(monday + dt.timedelta(days=6)), 2.0, 3.0)] if chain == "Jumbo" else []
        products = [Product("p", "Kipfilet 500 g", 5.0, "500 g")] if chain == "Albert Heijn" else []
        return offers, products

    def run_update(self, now, forced=()):
        with mock.patch.object(cli.openprices, "fetch", self.fake_fetch):
            return cli.update(self.db, now, forced)

    def test_every_store_is_fetched_once_a_day(self):
        requests = self.run_update(at("2026-10-15 07:00"))
        self.assertEqual(sorted(self.calls), sorted(store.osm_name for store in STORES))
        self.assertEqual(requests, 2 * len(STORES))

        self.calls.clear()
        self.assertIsNone(self.run_update(at("2026-10-15 18:00")), "same day: nothing to do")
        self.assertEqual(self.calls, [])
        self.run_update(at("2026-10-16 07:00"))
        self.assertEqual(len(self.calls), len(STORES), "the next day, everything again")

    def test_a_forced_store_is_fetched_again_the_same_day(self):
        self.run_update(at("2026-10-15 07:00"))
        self.calls.clear()
        self.run_update(at("2026-10-15 09:00"), forced=["jumbo"])
        self.assertEqual(self.calls, ["Jumbo"])

    def test_offers_and_shelf_prices_are_saved(self):
        self.run_update(at("2026-10-15 07:00"))
        self.assertEqual([row["store_id"] for row in self.db.current_offers(at("2026-10-15 07:00"))], ["jumbo"])
        self.assertEqual([row["name"] for row in self.db.catalog("ah")], ["Kipfilet 500 g"])
        self.assertIsNotNone(self.db.store("ah")["catalog_changed_at"])

    def test_export_credits_open_prices_and_says_when_the_next_update_is(self):
        now = at("2026-10-15 07:00")
        requests = self.run_update(now)
        meta = export.export(self.db, now, Path(self.folder.name), requests)
        self.assertEqual(meta["requests"]["thisRun"], requests)
        self.assertEqual(meta["nextUpdateAt"], utc(at("2026-10-16 06:00")), "tomorrow morning")
        self.assertEqual(meta["license"], "ODbL-1.0")
        self.assertIn("Open Food Facts contributors", meta["attribution"])
        poiesz = next(s for s in meta["stores"] if s["id"] == "poiesz")
        self.assertEqual(poiesz["updateDay"], "Sunday")
        for name in ("offers.json", "prices.json", "meta.json"):
            self.assertTrue((Path(self.folder.name) / name).exists())


if __name__ == "__main__":
    unittest.main()
