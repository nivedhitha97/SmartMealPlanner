"""Builds recipes.json, the recipes the app plans with, from the Wikibooks Cookbook.

    python3 -m recipes.build --out DIR [--pages saved.json]

Every recipe is a human-written Wikibooks Cookbook recipe (CC BY-SA 4.0). It is adapted only to fit the app:
ingredient amounts converted to grams and each ingredient named from a standard list (for the grocery list),
nutrition per 100 g from USDA FoodData Central (public domain), and the project's own price estimates. The method
is the authors' own text. Each recipe credits Wikibooks and links to the exact revision it came from and to its
authors (the page history); the adapted recipes are shared under CC BY-SA 4.0 too. Photos are included only when
Wikimedia Commons lists a free licence and an author to credit.
"""

import argparse
import datetime as dt
import html
import json
import re
import urllib.parse
import uuid
from pathlib import Path

from . import amounts, parse
from .wiki import Wiki

FOODS = json.loads(Path(__file__).with_name("foods.json").read_text(encoding="utf-8"))["foods"]
for food in FOODS:
    food["pattern"] = re.compile(food["match"], re.I)

LICENSE = "CC BY-SA 4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by-sa/4.0/"
WIKI = "https://en.wikibooks.org/w/index.php"
CHANGES = "Adapted for Smart Meal Planner: amounts converted to grams and ingredients named from a standard list."

MEAL_CATEGORIES = {"Main course recipes", "Soup recipes", "Stew recipes", "Salad recipes", "Dal recipes",
                   "Side dish recipes", "Recipes for curry", "Curry recipes", "Breakfast recipes", "Rice recipes",
                   "Pasta recipes", "Casserole recipes"}
NOT_MEALS = {"Dessert recipes", "Beverage recipes", "Drink recipes", "Cocktail recipes", "Sauce recipes",
             "Condiment recipes", "Cake recipes", "Cookie recipes", "Candy recipes", "Jam recipes",
             "Spice mix recipes", "Dip recipes", "Marinade recipes", "Bread recipes", "Baking recipes",
             "Incomplete recipes", "Pickle recipes", "Snack recipes", "Appetizer recipes"}
CUISINES = {
    "Indian": {"Indian", "South Indian", "Pakistani", "Sindhi", "Bengali", "Punjabi", "Sri Lankan", "Nepali",
               "South Asian", "Goan", "Gujarati", "Kerala", "Tamil", "Hyderabadi", "Bangladeshi"},
    "Asian": {"Asian", "Chinese", "Japanese", "Thai", "Korean", "Vietnamese", "Indonesian", "Filipino",
              "Malaysian", "Cambodian", "Burmese", "Singaporean", "Taiwanese", "Cantonese", "Sichuan", "Laotian"},
    "Italian": {"Italian", "Sicilian", "Tuscan"},
    "Mexican": {"Mexican", "Tex-Mex"},
    "Greek": {"Greek", "Cypriot"},
    "French": {"French", "Provençal", "Breton"},
    "Dutch": {"Dutch", "Flemish", "Belgian"},
}
FREE_IMAGE_LICENSES = re.compile(r"^(public domain|pd\b|cc0|cc[- ]by(-sa)?[- ]?\d(\.\d)?|cc by(-sa)? \d)", re.I)
MAX_RECIPES = 1500

# Seasonings named without an amount ('salt to taste'): a typical pinch, so they appear in the list.
UNMEASURED = {"Salt": 2, "Black Pepper": 1, "Cayenne Pepper": 0.5, "Chili Flakes": 0.5, "Fresh Coriander": 5,
              "Parsley": 5, "Basil": 3, "Mint": 3, "Dill": 2, "Chives": 3, "Vegetable Oil": 10, "Olive Oil": 10,
              "Lemon Juice": 10, "Lime Juice": 10, "Turmeric": 1, "Chili Powder": 1, "Paprika Powder": 1,
              "Sugar": 4, "Ghee": 10, "Butter": 10, "Curry Leaves": 1, "Garam Masala": 1, "Flour": 10,
              "Soy Sauce": 10, "Milk": 30, "Honey": 10, "Mustard": 5, "Oregano": 1, "Nutmeg": 0.5,
              "Worcestershire Sauce": 5, "Vinegar": 5, "Balsamic Vinegar": 5, "Cumin": 1, "Parmesan Cheese": 10,
              "Cornstarch": 5, "Breadcrumbs": 10, "Cinnamon": 1, "Sesame Seeds": 3, "Sesame Oil": 5,
              "Cornmeal": 10, "Lettuce": 30, "Mixed Herbs": 1, "Allspice": 0.5, "Spirits": 15, "Hot Sauce": 3,
              "Tomato Ketchup": 10, "Fish Sauce": 5, "Garlic": 3, "Lemon": 30, "Lime": 30, "Olives": 20,
              "Thyme": 1, "Rosemary": 1, "Bay Leaves": 0.2, "Garlic Powder": 1, "Onion Powder": 1,
              "Smoked Paprika": 1, "Coriander Seeds": 1, "Mustard Seeds": 1, "Cloves": 0.3, "Cardamom": 0.5,
              "Sage": 1, "Fenugreek": 1, "Asafoetida": 0.2, "Saffron": 0.1, "Annatto": 1, "Chili Peppers": 10,
              "Spring Onions": 15, "Coconut Milk": 50, "Chicken Stock": 100, "Tomato Paste": 15, "Capers": 10,
              "Heavy Cream": 30, "Yogurt": 30, "Mayonnaise": 15, "Barbecue Sauce": 30, "Oyster Sauce": 10}
# Juice of a fruit, in grams.
JUICE = {"lemon": 45, "lime": 30, "orange": 85}
# Large cuts named by the piece ('1 whole chicken', '1 slab spareribs'), in grams.
CUTS = [(r"\bwhole chicken\b|\bchicken, whole\b", 1400), (r"\b(slab|rack)s?\b", 1300),
        (r"\broast\b|\bloin\b|\bshoulder\b|\bleg of\b", 1000), (r"\bchops?\b", 250), (r"\bsteaks?\b", 300),
        (r"\bfillets?\b|\bfilets?\b", 150), (r"\bbreasts?\b", 250), (r"\bthighs?\b|\bdrumsticks?\b", 120),
        (r"\bwings?\b|\bwingettes?\b", 45)]
DEFAULT_PIECE = {"Garlic": 3, "Ginger": 15, "Chili Peppers": 15, "Bay Leaves": 0.2, "Curry Leaves": 0.1,
                 "Cardamom": 0.2, "Cloves": 0.1, "Cinnamon": 2.5, "Lime": 67, "Lemon": 58, "Eggs": 50,
                 "Tortillas": 45, "Bread": 30, "Chicken Thighs": 150, "Sausage": 75, "Avocado": 170,
                 "Shallots": 30, "Sweet Potatoes": 130, "Eggplant": 450, "Cucumber": 300}


def food_for(name, text):
    for food in FOODS:
        if food["pattern"].search(name):
            return food
    for food in FOODS:  # the name part can miss it ('2 cups of the cooked rice'); try the whole line
        if food["pattern"].search(text.lower()):
            return food
    return None


def grams_of(amount, food):
    """The line's amount in grams, or None when it can't be told."""
    if amount.grams:
        return amount.grams
    cup = food.get("gramsPerCup")
    density = (cup / 240) if cup else 1.0
    if amount.millilitres:
        return amount.millilitres * density
    if amount.quantity is None:
        return UNMEASURED.get(food["name"])
    q = amount.quantity
    unit = amount.unit
    if unit in ("cup", "tbsp", "tsp"):
        per = {"cup": food.get("gramsPerCup"), "tbsp": food.get("gramsPerTbsp"), "tsp": food.get("gramsPerTsp")}[unit]
        if per is None and cup:
            per = cup / {"cup": 1, "tbsp": 16, "tsp": 48}[unit]
        if per is None:
            per = {"cup": 240, "tbsp": 15, "tsp": 5}[unit] * (0.45 if food["name"] in SPICES else 1.0)
        return q * per
    if unit == "clove":
        return q * (food.get("gramsPerClove") or 3)
    if unit in ("pinch",):
        return q * amounts.UNITS["pinch"][1]
    if unit in ("can", "slice", "bunch", "handful", "sprig", "stick", "stalk", "head"):
        return q * {"can": 400, "slice": 30 if food["name"] != "Bacon" else 12, "bunch": 40, "handful": 30,
                    "sprig": 1, "stick": 113, "stalk": food.get("gramsPerPiece") or 40,
                    "head": food.get("gramsPerPiece") or 500}[unit]
    if unit in (None, "piece"):
        if food["name"] in ("Pork", "Beef", "Lamb", "Chicken", "Chicken Thighs", "Turkey", "Duck", "White Fish",
                            "Salmon"):
            for pattern, weight in CUTS:
                if re.search(pattern, amount.text, re.I):
                    return q * weight
        piece = food.get("gramsPerPiece") or DEFAULT_PIECE.get(food["name"])
        return q * piece * amount.size if piece else None
    return None


SPICES = {"Garlic Powder", "Onion Powder", "Black Pepper", "Cayenne Pepper", "Chili Flakes", "Chili Powder",
          "Smoked Paprika", "Paprika Powder", "Garam Masala", "Curry Powder", "Turmeric", "Cumin", "Coriander Seeds",
          "Mustard Seeds", "Fenugreek", "Asafoetida", "Cardamom", "Cloves", "Cinnamon", "Nutmeg", "Oregano", "Thyme",
          "Rosemary", "Sage"}
NOT_INGREDIENTS = re.compile(
    r"\b(bowls?|pots?|pans?|knife|knives|oven|skillets?|stove(top)?|grill|baking (sheet|dish|tray)|saucepan|wok|"
    r"plates?|blender|spoons?|toothpicks?|skewers?|(aluminum |aluminium )?foil|parchment|whisk|spatulas?|"
    r"charcoal|chimney( starter)?|cutting board|briquets?|burner|toaster|skimmer|thermometer|tongs|colander|"
    r"sieve|ladle|processor|mortar|pestle|paellera|barbecue grill|smoker|"
    r"(hickory|mesquite|applewood|apple wood|oak|cherry|wood) (chips|chunks))\b|^a low\b", re.I)


def ingredients_of(lines):
    """The recipe's ingredients ({food, grams}) merged by food, or None if any line can't be read reliably."""
    merged = {}
    for line in lines:
        if NOT_INGREDIENTS.search(line) or line.endswith(":"):
            continue
        juice = re.match(r"^(?:the\s+)?(?:juice|zest|juice and zest) of\s+(\S+)\s+(lemon|lime|orange)s?\b", line, re.I)
        if juice:
            count = amounts.number(juice.group(1)) or (1 if juice.group(1).lower() in ("a", "an", "one") else None)
            fruit = juice.group(2).lower()
            if count:
                name = {"lemon": "Lemon Juice", "lime": "Lime Juice", "orange": "Oranges"}[fruit]
                food = next(f for f in FOODS if f["name"] == name)
                merged.setdefault(food["name"], [food, 0.0])[1] += count * JUICE[fruit]
                continue
        amount = amounts.read(line)
        if not amount.name and amount.quantity is None:
            continue
        food = food_for(amount.name, line)
        if food is None:
            return None
        if food.get("skip"):
            continue
        grams = grams_of(amount, food)
        if grams is None or not 0 < grams <= 5000:
            return None
        merged.setdefault(food["name"], [food, 0.0])[1] += grams
    return [{"food": food, "grams": grams} for food, grams in merged.values()]


def meals_for(categories, fields):
    names = set(categories) | {fields.get("category", "")}
    if "Breakfast recipes" in names:
        return ["Breakfast"]
    return ["Lunch", "Dinner"]


# Well-known dish names, for recipes without a cuisine category.
DISH_CUISINES = [
    ("Indian", r"\b(masala|curry|dal|dhal|daal|biryani|tikka|korma|vindaloo|paneer|chana|chole|aloo|gobi|palak|"
               r"sambar|rasam|upma|poha|dosa|idli|pulao|pilau|raita|tandoori|saag|bhaji|pakora|kofta)\b"),
    ("Italian", r"\b(pasta|spaghetti|risotto|lasagn[ae]|penne|gnocchi|minestrone|frittata|carbonara|bolognese|"
                r"pesto|bruschetta|caprese|focaccia|polenta|ravioli|tortellini|osso buco|cacciatore|piccata|"
                r"marsala|parmigiana|primavera|puttanesca|arrabbiata|fettuccine|linguine|alfredo)\b"),
    ("Mexican", r"\b(taco|tacos|enchiladas?|burritos?|quesadillas?|fajitas?|chili con carne|salsa|tamales?|"
                r"pozole|mole|guacamole|nachos|huevos rancheros|chilaquiles|carnitas|tostadas?)\b"),
    ("Asian", r"\b(stir[- ]?fry|stir[- ]?fried|teriyaki|fried rice|lo mein|chow mein|pad thai|ramen|udon|"
              r"sushi|tempura|kung pao|sweet and sour|satay|nasi|bami|mie|pho|bibimbap|kimchi|dumplings?|"
              r"tofu|miso|szechuan|sichuan|gado[- ]gado|rendang|laksa|tom yum|green curry|red curry)\b"),
    ("Greek", r"\b(moussaka|souvlaki|tzatziki|spanakopita|gyros?|greek|dolmades|pastitsio|avgolemono|horiatiki|"
              r"stifado|gemista|fasolada)\b"),
    ("French", r"\b(ratatouille|quiche|coq au vin|bourguignon|croque|cassoulet|bouillabaisse|nicoise|niçoise|"
               r"gratin|vichyssoise|crêpes?|crepes?|omelette|velouté|veloute|provençal|provencal)\b"),
    ("Dutch", r"\b(stamppot|hutspot|erwtensoep|snert|boerenkool|zuurkool|hachee|bitterballen|poffertjes|"
              r"pannenkoeken|draadjesvlees|andijvie)\b"),
]


def cuisine_for(categories, name=""):
    for cuisine, names in CUISINES.items():
        if any(f"{n} recipes" in categories for n in names):
            return cuisine
    for cuisine, pattern in DISH_CUISINES:
        if re.search(pattern, name, re.I):
            return cuisine
    for category in categories:
        match = re.fullmatch(r"(?!Main|Side|Soup|Easy|Medium|Very|Difficult|Inexpensive|Vegan|Vegetarian|Gluten|"
                             r"Naturally|Kid|Halal|Kosher|Pescatarian|Public|Featured|Boiled|Baked|Fried|Pan|"
                             r"Deep|Grilled|Roasted|Steamed|Stir|Slow|Braised|Broiled|Smoked|Microwave|Camping|"
                             r"Refrigerated|Fermented|Christmas|Holiday|Breakfast|Salad|Dal|Stew|Rice|Pasta|"
                             r"Casserole|Dumpling|Barbecue|Curry)([A-Z][\w.' -]+) recipes", category)
        if match:
            return match.group(1)
    return "International"


def image_credit(info):
    """A photo with a free licence and an author to credit, or None."""
    if not info or not info.get("thumbURL") or not FREE_IMAGE_LICENSES.search(info.get("license") or ""):
        return None
    artist = re.sub(r"<[^>]+>", "", html.unescape(info.get("artist") or "")).strip()
    artist = re.sub(r"\s+", " ", artist)
    if not artist and not (info.get("license") or "").lower().startswith(("public domain", "pd", "cc0")):
        return None
    return {"imageURL": info["thumbURL"], "imageAuthor": artist[:120] or "Unknown author",
            "imageLicense": info["license"], "imageLicenseURL": info.get("licenseURL"),
            "imageSourceURL": info.get("pageURL")}


def recipe_from(page, image=None):
    text = page.get("text") or ""
    categories = page["categories"]
    if not (set(categories) & MEAL_CATEGORIES) or set(categories) & NOT_MEALS:
        return None
    fields = parse.summary(text)
    lines = parse.ingredient_lines(text)
    steps = parse.steps(text)
    if len(lines) < 3 or len(steps) < 2:
        return None
    ingredients = ingredients_of(lines)
    if not ingredients or len(ingredients) < 3:
        return None
    servings = parse.servings(fields) or 4
    title = page["title"]
    quoted = urllib.parse.quote(title.replace(" ", "_"))
    recipe = {
        "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"https://en.wikibooks.org/?curid={page['pageid']}")).upper(),
        "name": parse.name(title),
        "cuisine": cuisine_for(categories, parse.name(title)),
        "servings": servings,
        "totalMinutes": parse.minutes(fields),
        "meals": meals_for(categories, fields),
        "ingredients": [{
            "name": item["food"]["name"],
            "grams": max(1, round(item["grams"])),
            "caloriesPer100g": item["food"]["kcal"],
            "proteinPer100g": item["food"]["protein"],
            "carbsPer100g": item["food"]["carbs"],
            "fatPer100g": item["food"]["fat"],
            "pricePer100g": item["food"]["pricePer100g"],
        } for item in ingredients],
        "steps": steps[:30],
        "originalIngredients": lines,
        "sourceName": "Wikibooks Cookbook",
        "sourceURL": f"{WIKI}?title={quoted}&oldid={page['revid']}",
        "authorsURL": f"{WIKI}?title={quoted}&action=history",
        "license": LICENSE,
        "licenseURL": LICENSE_URL,
        "changes": CHANGES,
    }
    if image:
        recipe.update(image)
    return recipe


def build(pages, wiki=None):
    """The app's recipes from Cookbook pages ({title: page}); photos are looked up when `wiki` is given."""
    candidates = [r for r in (recipe_from(p) for p in pages.values()) if r]
    if wiki:
        by_name = {parse.name(p["title"]): p.get("image") for p in pages.values()}
        images = wiki.image_info([by_name[r["name"]] for r in candidates if by_name.get(r["name"])])
        for recipe in candidates:
            credit = image_credit(images.get(by_name.get(recipe["name"]) or ""))
            if credit:
                recipe.update(credit)
    candidates.sort(key=lambda r: r["name"])
    return candidates[:MAX_RECIPES]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, required=True, help="folder to write recipes.json and its licence to")
    parser.add_argument("--pages", type=Path, help="use pages saved earlier instead of fetching them")
    args = parser.parse_args(argv)
    wiki = Wiki()
    if args.pages:
        pages = json.loads(args.pages.read_text(encoding="utf-8"))
    else:
        pages = wiki.pages(wiki.recipe_titles())
    recipes = build(pages, wiki)
    args.out.mkdir(parents=True, exist_ok=True)
    feed = {
        "generatedAt": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "source": "Wikibooks Cookbook (en.wikibooks.org/wiki/Cookbook)",
        "license": LICENSE,
        "licenseURL": LICENSE_URL,
        "attribution": "Recipes from the Wikibooks Cookbook by its contributors, CC BY-SA 4.0; each recipe links "
                       "to its source revision and authors. " + CHANGES + " Nutrition: USDA FoodData Central "
                       "(public domain). Prices: the project's own estimates.",
        "recipes": recipes,
    }
    (args.out / "recipes.json").write_text(json.dumps(feed, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    (args.out / "RECIPES-LICENSE.md").write_text(RECIPES_LICENSE, encoding="utf-8")
    print(f"{len(recipes)} recipes ({sum(1 for r in recipes if r.get('imageURL'))} with photos), "
          f"{wiki.requests} requests")


RECIPES_LICENSE = f"""# Smart Meal Planner recipes: licence

recipes.json holds recipes from the [Wikibooks Cookbook](https://en.wikibooks.org/wiki/Cookbook), written by its
contributors and licensed under [{LICENSE}]({LICENSE_URL}). Each recipe's `sourceURL` links to the exact page
revision it was taken from, and `authorsURL` to the page history listing its authors.

{CHANGES} Nutrition values per 100 g come from USDA FoodData Central (public domain, CC0 1.0); prices are the
project's own estimates. These adapted recipes are shared under the same licence, {LICENSE}.

Photos: where a recipe has `imageURL`, the photo is from Wikimedia Commons under the licence in `imageLicense`, by
`imageAuthor`; see `imageSourceURL` for its details.
"""


if __name__ == "__main__":
    main()
