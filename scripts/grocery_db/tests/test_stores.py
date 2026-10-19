"""Store parsers, on small samples shaped like each site's real data."""

import datetime as dt
import json
import unittest

from grocery_db import pagedata
from grocery_db.stores import detailresult, hoogvliet, jumbo, lidl, openprices, poiesz


def nuxt(table):
    return f'<html><script type="application/json" id="__NUXT_DATA__">{json.dumps(table)}</script></html>'


def next_data(data):
    return f'<html><script id="__NEXT_DATA__" type="application/json">{json.dumps(data)}</script></html>'


class PageDataTests(unittest.TestCase):
    def test_nuxt_payload_is_decoded_from_its_index_table(self):
        table = [["ShallowReactive", 1], {"data": 2}, {"offers": 3}, [4], {"name": 5, "price": 6}, "Kaas", 2.5]
        self.assertEqual(pagedata.page_data(nuxt(table)), {"data": {"offers": [{"name": "Kaas", "price": 2.5}]}})

    def test_next_data_is_plain_json(self):
        self.assertEqual(pagedata.page_data(next_data({"props": {"a": 1}})), {"props": {"a": 1}})

    def test_page_without_data_gives_none(self):
        self.assertIsNone(pagedata.page_data("<html></html>"))

    def test_find_objects_searches_nested_lists_and_dicts(self):
        data = {"a": [{"id": 1, "x": 1}, {"b": {"id": 2, "x": 2}}], "c": {"id": 3}}
        self.assertEqual(sorted(o["id"] for o in pagedata.find_objects(data, ["id", "x"])), [1, 2])


class StoreParserTests(unittest.TestCase):
    def test_lidl_item_with_lidl_plus_price_and_dates(self):
        item = {"gridbox": {"data": {
            "productId": 101, "fullTitle": "ZWAGERMAN Kipfilet", "canonicalUrl": "/p/kipfilet/p101",
            "storeStartDate": 1791756000, "storeEndDate": 1792360799, "image": "https://www.lidl.nl/assets/kip.png",
            "price": {"packaging": {"text": "400 g"}, "discount": {"percentageDiscount": 20}},
            "lidlPlus": [{"price": {"price": 2.29}}]}}}
        offer = lidl.parse_item(item)
        self.assertEqual((offer.key, offer.offer_price, offer.size), ("101", 2.29, "400 g"))
        self.assertEqual(offer.deal_text, "-20% met Lidl Plus")
        self.assertEqual(offer.valid_from, "2026-10-12T00:00:00+02:00")
        self.assertEqual(offer.valid_to, "2026-10-18T23:59:59+02:00")
        self.assertEqual(offer.url, "https://www.lidl.nl/p/kipfilet/p101")
        self.assertEqual(offer.image_url, "https://www.lidl.nl/assets/kip.png")

    def test_lidl_item_without_price_or_dates_is_skipped(self):
        self.assertIsNone(lidl.parse_item({"gridbox": {"data": {"storeStartDate": 1, "storeEndDate": 2, "price": {}}}}))

    def test_jumbo_promotions_keep_the_deal_and_exact_times(self):
        table = [{"promos": 1}, [2], {"id": 3, "title": 4, "subtitle": 5, "isKiesAndMix": 6, "hidden": 6,
                                      "start": 7, "end": 9, "tags": 11, "url": 13, "image": 15},
                 "3021283", "Campina vla", "Alle pakken à 1 liter", False,
                 {"iso": 8}, "2026-10-14T00:01:00+02:00", {"iso": 10}, "2026-10-20T23:59:59+02:00",
                 [12], {"text": 14}, "/aanbiedingen/campina-vla/3021283", "1+1 gratis",
                 "https://www.jumbo.com/INTERSHOP/static/vla.png"]
        table[12] = {"text": 14}
        [offer] = jumbo.parse_page(nuxt(table))
        self.assertEqual((offer.key, offer.title, offer.deal_text), ("3021283", "Campina vla", "1+1 gratis"))
        self.assertIsNone(offer.offer_price)
        self.assertEqual((offer.valid_from, offer.valid_to), ("2026-10-14T00:01:00+02:00", "2026-10-20T23:59:59+02:00"))
        self.assertEqual(offer.image_url, "https://www.jumbo.com/INTERSHOP/static/vla.png")

    def test_dirk_dates_are_local_calendar_dates(self):
        table = [{"offers": 1}, [2], {"offerId": 3, "headerText": 4, "packaging": 5, "offerPrice": 6,
                                      "normalPrice": 7, "startDate": 8, "endDate": 9, "textPriceSign": 10,
                                      "products": 11},
                 139851, "Hollandse aardbeien", "Bak 400 gram.", 2.49, 2.99,
                 "2026-10-14T00:00:00.000Z", "2026-10-20T23:59:00.000Z", "ACTIE_",
                 [12], {"productInformation": 13}, {"image": 14}, "artikelen/243172_1.png"]
        [offer] = detailresult.parse_page(nuxt(table), "https://www.dirk.nl/aanbiedingen")
        self.assertEqual((offer.title, offer.offer_price, offer.regular_price), ("Hollandse aardbeien", 2.49, 2.99))
        self.assertEqual(offer.size, "Bak 400 gram")
        self.assertIsNone(offer.deal_text, "'ACTIE_' is a placeholder")
        self.assertEqual(offer.valid_from, "2026-10-14T00:00:00+02:00")
        self.assertEqual(offer.valid_to, "2026-10-20T23:59:59+02:00")
        self.assertEqual(offer.image_url, "https://web-fileserver.dirk.nl/artikelen/243172_1.png?width=300",
                         "the first product's photo, resized")

    def test_dekamarkt_midnight_end_date_means_the_day_before(self):
        table = [{"offers": 1}, [2], {"offerId": 3, "headerText": 4, "offerPrice": 5, "normalPrice": 6,
                                      "startDate": 7, "endDate": 8, "textPriceSign": 9},
                 137768, "Friesche Vlag", 0.99, 1.55, "2026-10-13T00:00:00.000Z", "2026-10-20T00:00:00.000Z",
                 "2 voor 0,99"]
        [offer] = detailresult.parse_page(nuxt(table), "https://www.dekamarkt.nl/aanbiedingen")
        self.assertEqual(offer.valid_to, "2026-10-19T23:59:59+02:00")
        self.assertEqual(offer.deal_text, "2 voor 0,99")
        self.assertIsNone(offer.image_url, "no product photo")

    def test_hoogvliet_items_use_their_promotion_period(self):
        page = next_data({"props": {"pageProps": {"promotionPeriods": [{
            "weekNr": "2026-42", "validFrom": "2026-10-14 00:00:00", "validTo": "2026-10-20 23:59:59",
            "groups": [{"name": "Zuivel", "items": [{
                "sku": "123", "name": "Hak", "url_key": "hak-123",
                "thumbnail": {"url": "https://static.hoogvliet.nl/ecom/product/123.jpg"},
                "price_range": {"minimum_price": {"regular_price": {"value": 9.78}, "final_price": {"value": 4.89}}},
                "promotion_meta_data": {"korting_label": "1 + 1 Gratis"}}]}]}]}}})
        [offer] = hoogvliet.parse_page(page)
        self.assertEqual((offer.key, offer.offer_price, offer.regular_price), ("123@2026-42", 4.89, 9.78))
        self.assertEqual((offer.deal_text, offer.category), ("1 + 1 Gratis", "Zuivel"))
        self.assertEqual(offer.url, "https://hoogvliet.nl/product/hak-123")
        self.assertEqual(offer.image_url, "https://static.hoogvliet.nl/ecom/product/123.jpg")
        self.assertEqual(offer.valid_to, "2026-10-20T23:59:59+02:00")

    def test_poiesz_offer_lines_become_the_deal(self):
        table = [{"offers": 1}, [2], {"id": 3, "commercialTextLine1": 4, "offerTypeLine1": 5, "newPriceLow": 6,
                                      "validFrom": 7, "validUntil": 8, "commercialTextDetailsLine2": 9,
                                      "imageFile": 10},
                 130167, "Wagner piccolinis", "2 voor", 5.0, "2026-10-11T00:00:00", "2026-10-18T00:00:00", "doos à 9 stuks",
                 "files\\1\\8\\0\\5\\8\\3\\130167.psd"]
        [offer] = poiesz.parse_page(nuxt(table))
        self.assertEqual((offer.title, offer.offer_price, offer.deal_text), ("Wagner piccolinis", 5.0, "2 voor"))
        self.assertEqual((offer.valid_from, offer.valid_to), ("2026-10-11T00:00:00+02:00", "2026-10-17T23:59:59+02:00"))
        self.assertEqual(offer.image_url,
                         "https://files.poiesz-supermarkten.nl/files/1/8/0/5/8/3/130167.psd?width=300&mode=fill")


if __name__ == "__main__":
    unittest.main()


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
        self.assertEqual(offer.deal_text, "Bonus met Bonuskaart")
        self.assertEqual(offer.url, "https://prices.openfoodfacts.org/prices/36400")
        self.assertEqual(offer.image_url, "https://images.openfoodfacts.org/kip.jpg")

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

    def test_fetch_uses_only_dutch_ah_stores_and_keeps_the_latest_sighting(self):
        class FakeHttp:
            def __init__(self):
                self.urls = []

            def json(self, url, headers=None):
                self.urls.append(url)
                if "/locations?" in url:
                    return {"pages": 1, "items": [{"id": 7, "osm_name": "Albert Heijn XL"},
                                                  {"id": 8, "osm_name": "Café bij de Albert Heijn"}]}
                older = {**OpenPricesTests.PRICE, "id": 1, "price": 2.10, "date": "2026-10-12"}
                return {"pages": 1, "items": [OpenPricesTests.PRICE, older]}

        http = FakeHttp()
        offers = openprices.fetch_ah_offers(http, today=dt.date(2026, 10, 16))
        self.assertEqual([o.offer_price for o in offers], [1.99])
        prices_url = http.urls[1]
        self.assertIn("location_id__in=7&", prices_url)
        self.assertIn("price_is_discounted=true", prices_url)
        self.assertIn("date__gte=2026-10-09", prices_url)
