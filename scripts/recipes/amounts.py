"""Reads an ingredient line ('1 ½ cups (300 g) cooked rice, rinsed') into a quantity, a unit and the ingredient."""

import re
from dataclasses import dataclass
from typing import Optional

FRACTIONS = {"½": 0.5, "⅓": 1 / 3, "⅔": 2 / 3, "¼": 0.25, "¾": 0.75, "⅕": 0.2, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625,
             "⅞": 0.875, "⅙": 1 / 6}

# Unit words → (canonical unit, grams per unit if a weight, millilitres per unit if a volume).
UNITS = {
    "g": ("g", 1, None), "gram": ("g", 1, None), "grams": ("g", 1, None), "gm": ("g", 1, None), "gr": ("g", 1, None),
    "kg": ("g", 1000, None), "kilogram": ("g", 1000, None), "kilograms": ("g", 1000, None),
    "mg": ("g", 0.001, None),
    "oz": ("g", 28.35, None), "ounce": ("g", 28.35, None), "ounces": ("g", 28.35, None),
    "lb": ("g", 453.6, None), "lbs": ("g", 453.6, None), "pound": ("g", 453.6, None), "pounds": ("g", 453.6, None),
    "ml": ("ml", None, 1), "millilitre": ("ml", None, 1), "milliliter": ("ml", None, 1),
    "millilitres": ("ml", None, 1), "milliliters": ("ml", None, 1),
    "cl": ("ml", None, 10), "dl": ("ml", None, 100),
    "l": ("ml", None, 1000), "litre": ("ml", None, 1000), "liter": ("ml", None, 1000), "litres": ("ml", None, 1000),
    "liters": ("ml", None, 1000),
    "cup": ("cup", None, 240), "cups": ("cup", None, 240), "c": ("cup", None, 240),
    "tablespoon": ("tbsp", None, 15), "tablespoons": ("tbsp", None, 15), "tbsp": ("tbsp", None, 15),
    "tbs": ("tbsp", None, 15), "tbl": ("tbsp", None, 15), "tbsps": ("tbsp", None, 15), "T": ("tbsp", None, 15),
    "teaspoon": ("tsp", None, 5), "teaspoons": ("tsp", None, 5), "tsp": ("tsp", None, 5), "tsps": ("tsp", None, 5),
    "t": ("tsp", None, 5),
    "pint": ("ml", None, 473), "pints": ("ml", None, 473), "quart": ("ml", None, 946), "quarts": ("ml", None, 946),
    "fl oz": ("ml", None, 29.6), "fluid ounce": ("ml", None, 29.6), "fluid ounces": ("ml", None, 29.6),
    "pinch": ("pinch", 0.4, None), "pinches": ("pinch", 0.4, None), "dash": ("pinch", 0.6, None),
    "dashes": ("pinch", 0.6, None),
    "clove": ("clove", None, None), "cloves": ("clove", None, None),
    "can": ("can", 400, None), "cans": ("can", 400, None), "tin": ("can", 400, None), "tins": ("can", 400, None),
    "slice": ("slice", 30, None), "slices": ("slice", 30, None),
    "bunch": ("bunch", 50, None), "bunches": ("bunch", 50, None), "handful": ("handful", 30, None),
    "handfuls": ("handful", 30, None), "sprig": ("sprig", 1, None), "sprigs": ("sprig", 1, None),
    "stick": ("stick", 113, None), "sticks": ("stick", 113, None),
    "stalk": ("stalk", 40, None), "stalks": ("stalk", 40, None),
    "head": ("head", 500, None), "heads": ("head", 500, None),
    "piece": ("piece", None, None), "pieces": ("piece", None, None),
}
SIZE_WORDS = {"small": 0.7, "medium": 1.0, "large": 1.3, "big": 1.3, "extra-large": 1.5}
UNIT_PATTERN = "|".join(sorted((re.escape(u) for u in UNITS), key=len, reverse=True))


@dataclass
class Amount:
    quantity: Optional[float]   # None when the line gives none ('salt to taste')
    unit: Optional[str]         # 'g', 'ml', 'cup', 'tbsp', 'tsp', 'clove', 'can', ..., or None for pieces
    grams: Optional[float]      # when the line itself says (a weight, or a metric amount in brackets)
    millilitres: Optional[float]
    size: float                 # small / medium / large factor for pieces
    name: str                   # the ingredient, without amounts and preparation notes
    text: str                   # the whole line, as written


def number(text):
    """'1 ½', '1/2', '1-2', '2–3', '0.5', '½' → a number (a range gives its middle); None if there is none."""
    text = text.strip()
    for symbol, value in FRACTIONS.items():
        text = text.replace(symbol, f" {value}")
    parts = re.split(r"\s*(?:-|–|to|or)\s*", text, maxsplit=1)
    if len(parts) == 2 and parts[1]:
        low, high = number(parts[0]), number(parts[1])
        return (low + high) / 2 if low is not None and high is not None else low
    total, found = 0.0, False
    for token in text.split():
        if re.fullmatch(r"\d+/\d+", token):
            top, bottom = token.split("/")
            total += int(top) / int(bottom) if int(bottom) else 0
            found = True
        elif re.fullmatch(r"\d+(?:\.\d+)?", token):
            total += float(token)
            found = True
    return total if found else None


NUMBER = r"(?:\d+(?:\.\d+)?(?:\s+\d+/\d+)?|\d+/\d+|[½⅓⅔¼¾⅕⅛⅜⅝⅞⅙])(?:\s*[½⅓⅔¼¾⅕⅛⅜⅝⅞⅙])?"
RANGE = rf"{NUMBER}(?:\s*(?:-|–|to)\s*{NUMBER})?"


def read(line):
    """The amount and ingredient on an ingredient line."""
    text = line.strip()
    grams = millilitres = None
    # A metric amount in brackets wins: '1 cup (240 g)' or '2 cups (500 ml)'.
    for value, unit in re.findall(rf"\(\s*(?:about\s*|approx\.?\s*)?({RANGE})\s*({UNIT_PATTERN})\b", text, re.I):
        canonical = UNITS.get(unit) or UNITS.get(unit.lower())
        amount = number(value)
        if canonical and amount:
            if canonical[1] and canonical[0] == "g" and grams is None:
                grams = amount * canonical[1]
            elif canonical[2] and canonical[0] == "ml" and millilitres is None:
                millilitres = amount * canonical[2]
    body = re.sub(r"\([^)]*\)", " ", text)
    body = re.sub(r"\s+", " ", body).strip()
    quantity = unit = None
    match = re.match(rf"^(?:about\s+|approx\.?\s+)?({RANGE})\s*(.*)$", body, re.I)
    rest = body
    if match:
        quantity = number(match.group(1))
        rest = match.group(2)
        unit_match = re.match(rf"^({UNIT_PATTERN})\.?\b\s*(?:of\s+)?(.*)$", rest)
        if not unit_match:
            unit_match = re.match(rf"^({UNIT_PATTERN})\.?\b\s*(?:of\s+)?(.*)$", rest, re.I)
            if unit_match and unit_match.group(1) in ("T", "t", "c"):
                unit_match = None  # single letters only count in their usual case
        if unit_match:
            canonical = UNITS.get(unit_match.group(1)) or UNITS.get(unit_match.group(1).lower())
            unit = canonical[0]
            if canonical[1] and grams is None and canonical[0] in ("g",):
                grams = quantity * canonical[1]
            if canonical[2] and millilitres is None and canonical[0] in ("ml",):
                millilitres = quantity * canonical[2]
            rest = unit_match.group(2)
    else:
        unit_match = re.match(rf"^(?:a|an|one)\s+({UNIT_PATTERN})\b\s*(?:of\s+)?(.*)$", body, re.I)
        if unit_match:
            quantity = 1.0
            unit = (UNITS.get(unit_match.group(1)) or UNITS.get(unit_match.group(1).lower()))[0]
            rest = unit_match.group(2)
    size = 1.0
    size_match = re.match(r"^(small|medium|large|big|extra-large)\b\s*(.*)$", rest, re.I)
    if size_match:
        size = SIZE_WORDS[size_match.group(1).lower()]
        rest = size_match.group(2)
    return Amount(quantity, unit, grams, millilitres, size, ingredient_name(rest), text)


def ingredient_name(text):
    """'finely chopped red onions, peeled' → 'finely chopped red onions' (the part before preparation notes)."""
    name = re.split(r",|;|\bfor\b|\bto taste\b|\bor to taste\b|\(|\bif\b|\bdivided\b", text, maxsplit=1)[0]
    name = re.sub(r"^\s*(of|x)\s+", "", name, flags=re.I)
    return re.sub(r"\s+", " ", name).strip(" .-*:").lower()
