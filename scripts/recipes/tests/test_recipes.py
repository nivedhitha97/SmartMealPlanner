"""The Wikibooks recipe importer, on small hand-written samples shaped like Cookbook pages."""

import unittest

from recipes import amounts, build, parse

PAGE_TEXT = """{{recipesummary|category=Main course recipes|servings=4-6|time=1 hour 20 minutes|difficulty=3
| Image = [[File:Dal.jpg|300px]]
}}
{{recipe}} | [[Cookbook:Cuisine of India|Indian recipes]]

'''Dal''' is a lentil dish.<ref>{{cite web|url=http://example.org}}</ref>

==Ingredients==
* 1 [[Cookbook:Cup|cup]] (200 g) red [[Cookbook:Lentil|lentils]], rinsed
* 2 [[Cookbook:Tablespoon|tablespoons]] [[Cookbook:Ghee|ghee]]
* 1 medium [[Cookbook:Onion|onion]], chopped
* 2 cloves [[Cookbook:Garlic|garlic]]
* Salt to taste
* Juice of 1 lemon
* 4 cups water

==Procedure==
# Boil the lentils in the water until soft.
# Fry the onion and garlic in the ghee, then stir into the lentils.
# Season with salt and lemon juice.

==Notes, tips, and variations==
* Serve with rice.
"""


def page(text=PAGE_TEXT, categories=("Indian recipes", "Main course recipes", "Vegetarian recipes")):
    return {"title": "Cookbook:Simple Dal", "pageid": 42, "revid": 1234, "text": text,
            "categories": list(categories)}


class ParseTests(unittest.TestCase):
    def test_markup_becomes_plain_text(self):
        self.assertEqual(parse.clean("[[Cookbook:Cup|cup]] of [[Cookbook:Rice]]<ref>x</ref> '''bold'''"),
                         "cup of Rice bold")

    def test_summary_fields_servings_and_time(self):
        fields = parse.summary(PAGE_TEXT)
        self.assertEqual(parse.servings(fields), 4)
        self.assertEqual(parse.minutes(fields), 80)

    def test_only_the_ingredient_list_and_the_numbered_method(self):
        self.assertEqual(len(parse.ingredient_lines(PAGE_TEXT)), 7, "notes after the method aren't ingredients")
        self.assertEqual(parse.steps(PAGE_TEXT)[0], "Boil the lentils in the water until soft.")


class AmountTests(unittest.TestCase):
    def test_metric_amount_in_brackets_wins(self):
        amount = amounts.read("1 cup (200 g) red lentils, rinsed")
        self.assertEqual((amount.grams, amount.unit, amount.name), (200, "cup", "red lentils"))

    def test_fractions_ranges_and_sizes(self):
        self.assertEqual(amounts.number("1 ½"), 1.5)
        self.assertEqual(amounts.number("4-5"), 4.5)
        self.assertAlmostEqual(amounts.number("1/3"), 1 / 3)
        amount = amounts.read("2 large potatoes, cubed")
        self.assertEqual((amount.quantity, amount.unit, amount.size, amount.name), (2, None, 1.3, "potatoes"))

    def test_unit_words_and_no_amount(self):
        self.assertEqual(amounts.read("2 tbsp olive oil").unit, "tbsp")
        self.assertIsNone(amounts.read("Salt to taste").quantity)


class BuildTests(unittest.TestCase):
    def test_a_cookbook_page_becomes_a_credited_recipe(self):
        recipe = build.recipe_from(page())
        self.assertEqual((recipe["name"], recipe["cuisine"], recipe["servings"], recipe["totalMinutes"]),
                         ("Simple Dal", "Indian", 4, 80))
        self.assertEqual(recipe["meals"], ["Lunch", "Dinner"])
        grams = {i["name"]: i["grams"] for i in recipe["ingredients"]}
        self.assertEqual(grams["Red Lentils"], 200)
        self.assertEqual(grams["Onion"], 110, "a medium onion, from USDA portion weights")
        self.assertEqual(grams["Lemon Juice"], 45, "the juice of a lemon")
        self.assertNotIn("Water", grams, "water isn't shopped for")
        self.assertEqual(recipe["steps"][2], "Season with salt and lemon juice.", "the authors' own words")
        self.assertEqual(recipe["sourceURL"],
                         "https://en.wikibooks.org/w/index.php?title=Cookbook%3ASimple_Dal&oldid=1234")
        self.assertTrue(recipe["authorsURL"].endswith("&action=history"))
        self.assertEqual(recipe["license"], "CC BY-SA 4.0")
        self.assertIn("amounts converted to grams", recipe["changes"])

    def test_the_same_page_always_gets_the_same_id(self):
        self.assertEqual(build.recipe_from(page())["id"], build.recipe_from(page())["id"])

    def test_desserts_drinks_and_unreadable_recipes_are_left_out(self):
        self.assertIsNone(build.recipe_from(page(categories=("Dessert recipes", "Main course recipes"))))
        self.assertIsNone(build.recipe_from(page(categories=("Indian recipes",))), "not a meal")
        unknown = PAGE_TEXT.replace("* 4 cups water", "* 3 tbsp unobtainium")
        self.assertIsNone(build.recipe_from(page(unknown)), "every ingredient must be known")

    def test_breakfasts_and_cuisines_from_dish_names(self):
        self.assertEqual(build.meals_for(["Breakfast recipes"], {}), ["Breakfast"])
        self.assertEqual(build.cuisine_for([], "Mushroom Risotto"), "Italian")
        self.assertEqual(build.cuisine_for(["Thai recipes"], "Anything"), "Asian")
        self.assertEqual(build.cuisine_for([], "Hutspot"), "Dutch")

    def test_peppers_are_told_apart(self):
        names = {line: build.food_for(amounts.read(line).name, line)["name"] for line in
                 ["1 tbsp cayenne pepper", "1 green bell pepper", "½ tsp red pepper flakes", "pepper to taste"]}
        self.assertEqual(list(names.values()), ["Cayenne Pepper", "Bell Pepper", "Chili Flakes", "Black Pepper"])

    def test_only_freely_licensed_photos_with_an_author(self):
        free = {"thumbURL": "https://upload.wikimedia.org/x.jpg", "license": "CC BY-SA 4.0", "artist": "<a>Ana</a>",
                "pageURL": "https://commons.wikimedia.org/wiki/File:X.jpg", "licenseURL": "https://cc.org"}
        self.assertEqual(build.image_credit(free)["imageAuthor"], "Ana")
        self.assertIsNone(build.image_credit({**free, "license": "Fair use"}))
        self.assertIsNone(build.image_credit({**free, "license": "GFDL"}), "GFDL needs its full text; not used")
        self.assertIsNone(build.image_credit({**free, "artist": ""}), "no author to credit")
        self.assertIsNotNone(build.image_credit({**free, "license": "Public domain", "artist": ""}))


if __name__ == "__main__":
    unittest.main()
