"""Builds foods.json, the importer's ingredient table, from foods_spec.py and USDA FoodData Central.

USDA FoodData Central (SR Legacy, April 2018) is public domain (CC0 1.0): https://fdc.nal.usda.gov/
Download and unzip FoodData_Central_sr_legacy_food_csv_2018-04.zip, then, from scripts/:

    python3 -m recipes.build_foods path/to/FoodData_Central_sr_legacy_food_csv_2018-04

For every ingredient it takes the best-matching USDA food's nutrition per 100 g (energy, protein, carbohydrate,
fat) and its portion weights (a cup, a tablespoon, a medium piece, a clove), used to turn recipe amounts into grams.
"""

import csv
import json
import re
import sys
from pathlib import Path

from .foods_spec import FOODS

NUTRIENTS = {"1008": "kcal", "1003": "protein", "1005": "carbs", "1004": "fat"}
OUT = Path(__file__).with_name("foods.json")


def load(folder):
    foods = {r["fdc_id"]: r["description"] for r in csv.DictReader(open(folder / "food.csv", encoding="utf-8"))}
    nutrients = {}
    for row in csv.DictReader(open(folder / "food_nutrient.csv", encoding="utf-8")):
        key = NUTRIENTS.get(row["nutrient_id"])
        if key:
            nutrients.setdefault(row["fdc_id"], {})[key] = float(row["amount"] or 0)
    portions = {}
    for row in csv.DictReader(open(folder / "food_portion.csv", encoding="utf-8")):
        if row["gram_weight"]:
            amount = float(row["amount"] or 1) or 1
            portions.setdefault(row["fdc_id"], []).append(
                ((row["modifier"] or row["portion_description"] or "").lower(), float(row["gram_weight"]) / amount))
    return foods, nutrients, portions


def best_food(query, foods, nutrients):
    words = query.lower().split()
    hits = [(fid, d) for fid, d in foods.items() if fid in nutrients and all(w in d.lower() for w in words)]
    if not hits:
        raise SystemExit(f"No USDA food matches '{query}'")
    hits.sort(key=lambda h: (len(h[1]), h[0]))
    return hits[0]


def portion(portions, *patterns):
    for pattern in patterns:
        for modifier, grams in portions:
            if re.search(pattern, modifier):
                return round(grams, 1)
    return None


def build(folder):
    foods, nutrients, portions = load(Path(folder))
    table = []
    for name, match, query, price in FOODS:
        entry = {"name": name, "match": match, "pricePer100g": price}
        if query is None:
            entry["skip"] = True
            table.append(entry)
            continue
        fdc_id, description = best_food(query, foods, nutrients)
        values = nutrients[fdc_id]
        own = portions.get(fdc_id, [])
        entry.update({
            "usdaFdcId": int(fdc_id),
            "usdaDescription": description,
            "kcal": round(values.get("kcal", 0), 1),
            "protein": round(values.get("protein", 0), 1),
            "carbs": round(values.get("carbs", 0), 1),
            "fat": round(values.get("fat", 0), 1),
            "gramsPerCup": portion(own, r"^cup\b", r"\bcup\b"),
            "gramsPerTbsp": portion(own, r"^tbsp\b", r"\btbsp\b", r"tablespoon"),
            "gramsPerTsp": portion(own, r"^tsp\b", r"\btsp\b", r"teaspoon"),
            "gramsPerPiece": portion(own, r"^medium\b", r"\bmedium\b", r"^large\b", r"\b(whole|each|fruit|piece|"
                                     r"breast|thigh|egg|link|patty|leaf|stalk|ear|spear)\b", r"^small\b"),
            "gramsPerClove": portion(own, r"\bclove\b"),
        })
        table.append(entry)
    return table


def main(argv=None):
    argv = argv or sys.argv[1:]
    if not argv:
        raise SystemExit(__doc__)
    table = build(argv[0])
    OUT.write_text(json.dumps({
        "source": "USDA FoodData Central, SR Legacy (April 2018), public domain (CC0 1.0), fdc.nal.usda.gov; "
                  "prices are the project's own estimates",
        "foods": table,
    }, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    for entry in table:
        if not entry.get("skip"):
            print(f"{entry['name']:22} {entry['usdaFdcId']:>7} {entry['kcal']:>6} "
                  f"cup={entry['gramsPerCup']} tbsp={entry['gramsPerTbsp']} piece={entry['gramsPerPiece']} "
                  f"| {entry['usdaDescription'][:70]}")


if __name__ == "__main__":
    main()
