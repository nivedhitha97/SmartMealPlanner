import unittest

from grocery_db import export


class DealTests(unittest.TestCase):
    def test_deal_text_is_normalised_and_non_deals_dropped(self):
        self.assertEqual(export.clean_deal("1 + 1 Gratis"), "1+1 gratis")
        self.assertEqual(export.clean_deal("25% KORTING"), "25% korting")
        for text in ("per stuk 1,99", "per pakje", "500 gram", "bij 12.50 gratis bezorging", "", None):
            self.assertIsNone(export.clean_deal(text), text)

    def test_bundle_totals_become_per_item_prices(self):
        self.assertEqual(export.per_item(4.99, 7.24, "2 voor"), (2.5, 3.62))
        self.assertEqual(export.per_item(1.49, 2.98, "1+1 gratis"), (0.74, 1.49))
        self.assertEqual(export.per_item(10.15, 30.45, "1+2 gratis"), (3.38, 10.15))
        self.assertEqual(export.per_item(5.0, None, "2 voor"), (2.5, None))

    def test_free_item_deal_without_a_regular_price_is_a_per_item_price(self):
        self.assertEqual(export.per_item(1.09, None, "1+1 gratis"), (0.55, 1.09))

    def test_single_item_prices_are_unchanged(self):
        self.assertEqual(export.per_item(2.29, 2.99, "-20%"), (2.29, 2.99))
        self.assertEqual(export.per_item(2.29, None, None), (2.29, None))

    def test_deal_price_from_the_shelf_price(self):
        cases = {"1+1 gratis": 1.0, "2+1 gratis": 1.33, "2e halve prijs": 1.5, "2 voor 3,00": 1.5,
                 "25% korting": 1.5, "voor 1,49": 1.49, "-50%": 1.0}
        for deal, expected in cases.items():
            self.assertEqual(export.deal_price(deal, 2.0), expected, deal)

    def test_deal_price_is_none_when_unknown_or_not_cheaper(self):
        self.assertIsNone(export.deal_price("op=op", 2.0))
        self.assertIsNone(export.deal_price("voor 2,49", 2.0))
        self.assertIsNone(export.deal_price("1+1 gratis", None))

    def test_unit_label_is_a_short_pack_size_or_item(self):
        self.assertEqual(export.unit_label("500 Gram"), "500 g")
        self.assertEqual(export.unit_label("Pak 1 liter"), "Pak 1 liter")
        for text in ("Alle soorten", "Bij 12,50 gratis bezorging", "", None, "Kuip 250 of 300 gram. OP=OP extra lang"):
            self.assertEqual(export.unit_label(text), "item", text)

    def test_category_does_not_match_inside_brand_names(self):
        from grocery_db.matching import category_for
        self.assertEqual(category_for("Iglo vissticks"), "Fish")
        self.assertNotEqual(category_for("Lay's of Duyvis"), "Fish")

    def test_two_for_label_gets_its_price(self):
        self.assertEqual(export._deal_label("2 voor", 5.0), "2 voor €5,00")
        self.assertEqual(export._deal_label("1+1 gratis", 5.0), "1+1 gratis")


class MatchingTests(unittest.TestCase):
    def test_promotion_matches_the_cheapest_product_with_all_its_words(self):
        products = [{"name": "Campina Vla Vanille 1 L", "price": 1.79, "size": "1 l"},
                    {"name": "Campina Vla Chocolade 1 L", "price": 1.59, "size": "1 l"},
                    {"name": "Campina Halfvolle Melk", "price": 1.19, "size": "1 l"}]
        match = export._cheapest_match("Campina vla", "", export._word_index(products))
        self.assertEqual(match["price"], 1.59)
        self.assertIsNone(export._cheapest_match("Alpro vla", "", export._word_index(products)))


if __name__ == "__main__":
    unittest.main()
