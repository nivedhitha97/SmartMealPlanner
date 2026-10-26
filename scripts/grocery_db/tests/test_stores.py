"""The Open Prices fetcher, on small samples shaped like its API's data."""

import datetime as dt
import unittest

from grocery_db.stores import STORES, openprices


class OpenPricesTests(unittest.TestCase):
    PRICE = {"id": 36400, "price": 1.99, "price_without_discount": 2.79, "price_is_discounted": True,
             "discount_type": "LOYALTY_PROGRAM", "currency": "EUR", "date": "2026-10-14", "product_code": "8718907",
             "product": {"product_name": "AH Kipfilet", "quantity": "300 g",
                         "image_url": "https://images.openfoodfacts.org/kip.jpg"}}

    def test_discount_becomes_an_offer_for_its_bonus_week(self):
        offer = openprices.parse_price(self.PRICE)
        self.assertEqual((offer.key, offer.title, offer.offer_price, offer.regular_price, offer.size),
                         ("8718907", "AH Kipfilet", 1.99, 2.79, "300 g"))
        self.assertEqual(offer.valid_from, "2026-10-12T00:00:00+02:00")  # Monday of the week it was seen
        self.assertEqual(offer.valid_to, "2026-10-18T23:59:59+02:00")    # that Sunday
        self.assertEqual(offer.deal_text, "Met klantenkaart")
        self.assertEqual(offer.url, "https://prices.openfoodfacts.org/prices/36400")
        self.assertIsNone(offer.image_url, "Open Food Facts photos have their own licence; they aren't used")

    def test_loose_produce_is_named_from_its_category_and_priced_per_kilo(self):
        item = {"id": 1, "price": 2.5, "currency": "EUR", "date": "2026-10-13", "category_tag": "en:pink-lady-apples",
                "price_per": "KILOGRAM", "product": None}
        offer = openprices.parse_price(item)
        self.assertEqual((offer.title, offer.size, offer.key), ("Pink lady apples", "1 kg", "en:pink-lady-apples"))

    def test_unusable_prices_are_skipped(self):
        self.assertIsNone(openprices.parse_price({**self.PRICE, "currency": "GBP"}))
        self.assertIsNone(openprices.parse_price({**self.PRICE, "price": None}))
        self.assertIsNone(openprices.parse_price({"id": 2, "price": 1.0, "date": "2026-10-14", "product": {}}))

    def test_regular_price_must_be_higher(self):
        self.assertIsNone(openprices.parse_price({**self.PRICE, "price_without_discount": 1.50}).regular_price)

    def test_fetch_uses_only_the_chains_dutch_stores_and_splits_offers_from_shelf_prices(self):
        shelf = {"id": 5, "price": 2.49, "price_is_discounted": False, "currency": "EUR", "date": "2026-09-20",
                 "product_code": "123", "product": {"product_name": "Volkoren pasta", "quantity": "500 g"}}
        old_discount = {**OpenPricesTests.PRICE, "id": 3, "product_code": "999", "date": "2026-09-01"}

        class FakeHttp:
            def __init__(self):
                self.urls = []

            def json(self, url, headers=None):
                self.urls.append(url)
                assert headers["User-Agent"].startswith("SmartMealPlanner/"), "an honest user agent"
                if "/locations?" in url:
                    return {"pages": 1, "items": [{"id": 7, "osm_name": "Albert Heijn XL"},
                                                  {"id": 8, "osm_name": "Café bij de Albert Heijn"}]}
                older = {**OpenPricesTests.PRICE, "id": 1, "price": 2.10, "date": "2026-10-12"}
                return {"pages": 1, "items": [OpenPricesTests.PRICE, older, shelf, old_discount]}

        http = FakeHttp()
        offers, products = openprices.fetch(http, "Albert Heijn", today=dt.date(2026, 10, 16))
        self.assertEqual([o.offer_price for o in offers], [1.99], "the latest sighting; older weeks aren't offers")
        self.assertEqual([(p.name, p.price, p.size) for p in products], [("Volkoren pasta", 2.49, "500 g")])
        prices_url = http.urls[1]
        self.assertIn("location_id__in=7&", prices_url)
        self.assertIn("date__gte=2026-07-18", prices_url)

    def test_no_locations_means_no_requests_for_prices(self):
        class FakeHttp:
            calls = 0

            def json(self, url, headers=None):
                FakeHttp.calls += 1
                return {"pages": 1, "items": []}

        self.assertEqual(openprices.fetch(FakeHttp(), "Vomar"), ([], []))
        self.assertEqual(FakeHttp.calls, 1)

    def test_every_store_is_fetched_from_open_prices_only(self):
        import grocery_db.stores as stores_module
        source = open(stores_module.__file__).read() + open(openprices.__file__).read()
        for site in ("jumbo.com", "lidl.nl", "dirk.nl", "dekamarkt.nl", "hoogvliet.nl", "poiesz-supermarkten.nl", "checkjebon"):
            self.assertNotIn(site, source)
        self.assertEqual(len({store.id for store in STORES}), len(STORES))
