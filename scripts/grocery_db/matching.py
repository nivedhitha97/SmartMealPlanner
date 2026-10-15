"""Recognising products: which recipe ingredient a product is, its weight, size label and category.

Product names are Dutch, as the supermarkets publish them.
"""

import re

# Product-name patterns (Dutch) for each recipe ingredient. "pieceGrams" prices products sold per piece.
INGREDIENTS = {
    "Rice": {"match": r"\b(basmati|jasmijn|witte|zilvervlies|pandan|langkorrel)\w*\s+rijst\b|^\w+ rijst\b"},
    "Arborio Rice": {"match": r"\barborio\b|\brisotto\s*rijst\b"},
    "Chicken Breast": {"match": r"\bkipfilet\b", "exclude": r"gerookt|beleg|flinterdun|salade|spread|soep|snack|gebraden|gegrild|gekruid|shoarma|reepjes|stukjes|cordon|schnitzel|nuggets"},
    "Salmon Fillet": {"match": r"\bzalm\s*filet", "exclude": r"gerookt|salade|spread|graved|snipper"},
    "Whole Wheat Pasta": {"match": r"\bvolkoren\b.*\b(pasta|penne|spaghetti|fusilli|macaroni|tagliatelle|farfalle)\b"},
    "Cherry Tomatoes": {"match": r"\b(cherry\s*tomaat|cherry\s*tomaten|cherrytomaatjes|snoeptomaat|snoeptomaten|snoeptomaatjes)\b", "exclude": r"saus|gedroogd|soep|blik"},
    "Cucumber": {"match": r"\bkomkommers?\b", "exclude": r"salade|water|drank|tzatziki|chips|zuur|augurk", "pieceGrams": 350},
    "Feta Cheese": {"match": r"\bfeta\b", "exclude": r"salade|spread|dip|olijven|wrap|pizza|bladerdeeg"},
    "Olives": {"match": r"\bolijven\b", "exclude": r"olie|tapenade|pizza|brood|crackers|chips"},
    "Black Beans": {"match": r"\bzwarte\s+bonen\b", "exclude": r"saus|chips|burger"},
    "Corn Tortillas": {"match": r"\b(mais|corn)\b.*\btortilla|\btortilla\w*\b.*\b(mais|corn)\b", "exclude": r"chips"},
    "Red Lentils": {"match": r"\brode\s+linzen\b", "exclude": r"soep|pasta|chips"},
    "Mushrooms": {"match": r"\bchampignons?\b", "exclude": r"soep|saus|pizza|roomsaus|risotto|pasta|pie|kaas"},
    "Parmesan Cheese": {"match": r"\b(parmigiano|parmezaan|parmesan|grana padano)\b", "exclude": r"chips|saus|pesto|crackers|kip|schnitzel|mezzelune|ravioli|tortellini|truffel|pasta"},
    "Broccoli": {"match": r"\bbroccoli\b", "exclude": r"soep|salade|rijst|mix|pizza|ovenschotel|quiche|burger", "pieceGrams": 500},
    "Bell Pepper": {"match": r"\bpaprika'?s?\b", "exclude": r"chips|poeder|saus|gerookt|spread|hummus|gedroogd|kruiden|chorizo|worst|ketchup|dip|chutney|gevuld|olie|tapenade|zuur|mix|rookworst|crackers|nootjes|aardappel", "pieceGrams": 160},
    "Eggs": {"match": r"\beieren\b", "exclude": r"salade|spread|noedels|pasta|chocolade|paas|spaghetti|bami|mie", "pieceGrams": 60},
    "Butter": {"match": r"\b(roomboter|boter)\b", "exclude": r"vla|taart|gebak|koek|cake|croissant|sprits|bladerdeeg|bonbon|biscuit|wafel|kaas|kruiden|knoflook|melk|pinda|ham|brioche|bisschop|stroop|chocola"},
}

# Product names that never belong in a grocery offers list for a meal planner.
NON_FOOD = re.compile(
    r"wasmiddel|wasverzachter|shampoo|douche|tandpasta|tandenborstel|luier|toiletpapier|wc-|deodorant|scheer|"
    r"batterij|kattenvoer|hondenvoer|kattenbak|hond|kat\b|vaatwas|afwas|schoonmaak|allesreiniger|bleek|"
    r"maandverband|tampon|zeep|bodylotion|crème|haar|make-up|nagel|kaars|vuilniszak|containerzak|aluminiumfolie|"
    r"tissues|zakdoek|keukenpapier|olvarit|\d+\s*(mnd|maanden)|\d+m\+|"
    r"ariel|lenor|robijn|dreft|persil|\bomo\b|sunil|\bfinish\b|dubro|dettol|ajax|vanish|harpic|libresse|tena\b|"
    r"always|pampers|aquafresh|listerine|andr[eé]lon|elvive|studio line|perfect fit|whiskas|felix|sheba|"
    r"potchrysant|chrysant|plant\b|bloemen|boeket|glorix|toiletblok|philips|lamp|\baxe\b|\bdove\b|rexona|"
    r"oral-b|colgate|prodent|zendium|wenskaart|swirl|toppits|curalyn|vitamine|jenever|beerenburg|"
    r"gato negro|los gansos|neleman|stoney creek|"
    r"wijn|bier|pils|whisky|wodka|vodka|\bgin\b|\brum\b|likeur|cider|prosecco|champagne|cava|port\b|sherry|"
    r"hertog jan|heineken|amstel|grolsch|bavaria|corona|brand\b|tripel|dubbel|\bipa\b|weizen|radler|krat\b|"
    r"pinot|primitivo|verdejo|merlot|cabernet|chardonnay|sauvignon|shiraz|malbec|rioja|lambrusco|ros[ée]\b",
    re.IGNORECASE)

CATEGORIES = [
    ("Snacks", r"chips|koek|chocola|snoep|reep|biscuit|nootjes|kruidnoten|drop\b|wafel|cake|bonbon|praline|chokotoff"),
    ("Drinks", r"water\b|\bcola\b|\bsap\b|frisdrank|\bthee\b|koffie|limonade|siroop|drink"),
    ("Meat", r"kip|vlees|gehakt|rund|varken|biefstuk|worst|spek|ham\b|kalkoen|schnitzel|burger|lam\b"),
    ("Fish", r"\bvis|zalm|tonijn|kabeljauw|garnalen|haring|makreel|pangasius|mosselen|schol"),
    ("Dairy", r"kaas|melk|yoghurt|kwark|boter|room\b|slagroom|eieren|\bei\b|feta|mozzarella|vla\b|skyr"),
    ("Produce", r"tomaat|tomaten|komkommer|paprika|sla\b|broccoli|wortel|ui\b|uien|appel|peer|banaan|"
                r"champignon|aardappel|courgette|spinazie|prei|pompoen|bloemkool|avocado|citroen|druiven|"
                r"bessen|aardbei|mandarijn|sinaasappel|kool\b|bonen|groente|fruit|kruiden"),
    ("Bakery", r"brood|bolletje|croissant|stokbrood|beschuit|crackers|wraps?\b|tortilla"),
    ("Pantry", r"rijst|pasta|spaghetti|penne|macaroni|noedels|mie\b|linzen|kikkererwten|meel|bloem\b|olie|"
               r"saus|soep|bouillon|kruiden|blik|pindakaas|jam|hagelslag|muesli|granola|cornflakes|havermout"),
    ]

# ---- Sizes and prices ----

_NUMBER = r"(\d+(?:[.,]\d+)?)"
_UNITS = {"kg": 1000, "kilo": 1000, "kilogram": 1000, "g": 1, "gr": 1, "gram": 1, "l": 1000, "liter": 1000,
          "ltr": 1000, "cl": 10, "centiliter": 10, "ml": 1, "milliliter": 1}
_UNIT = r"(kilogram|kilo|kg|gram|gr|g|liter|ltr|l|centiliter|cl|milliliter|ml)\b"


def grams(size, name="", piece_grams=None):
    """Weight in grams from a size label such as '500 g', 'ca. 1,2 kg', '2 x 125 g', '6 stuks' or 'per stuk'."""
    text = f"{size} {name}".lower().replace("\u202f", " ").replace("\xa0", " ")
    multi = re.search(_NUMBER + r"\s*[x×]\s*" + _NUMBER + r"\s*" + _UNIT, text)
    if multi:
        count, amount, unit = float(multi[1].replace(",", ".")), float(multi[2].replace(",", ".")), multi[3]
        return count * amount * _UNITS[unit]
    single = re.search(_NUMBER + r"\s*" + _UNIT, text)
    if single:
        return float(single[1].replace(",", ".")) * _UNITS[single[2]]
    if piece_grams:
        pieces = re.search(_NUMBER + r"\s*(stuks?|st\b|eieren)", text)
        if pieces:
            return float(pieces[1].replace(",", ".")) * piece_grams
        if re.search(r"\bper\s+stuk\b|\b1\s*stuk\b|\bstuk\b", text) or not size.strip():
            return piece_grams
    return None


def short_size(size):
    """'3000 Milliliter' → '3 l', '500 Gram' → '500 g', '6 Stuks' → '6 st'."""
    text = size.replace("\u202f", " ").strip()
    match = re.fullmatch(r"(?:per\s+)?" + _NUMBER + r"\s*([A-Za-z]+)\.?", text, re.IGNORECASE)
    if not match:
        return text
    amount, unit = float(match[1].replace(",", ".")), match[2].lower()
    if unit in ("milliliter", "ml") and amount >= 1000:
        amount, unit = amount / 1000, "l"
    elif unit in ("gram", "gr", "g") and amount >= 1000:
        amount, unit = amount / 1000, "kg"
    unit = {"milliliter": "ml", "centiliter": "cl", "liter": "l", "ltr": "l", "gram": "g", "gr": "g",
            "kilogram": "kg", "kilo": "kg", "stuks": "st", "stuk": "st"}.get(unit, unit)
    return f"{amount:g} {unit}"


def category_for(name):
    lowered = name.lower()
    for category, pattern in CATEGORIES:
        if re.search(pattern, lowered):
            return category
    return "Groceries"


def ingredient_for(name):
    for ingredient, rule in INGREDIENTS.items():
        if re.search(rule["match"], name, re.IGNORECASE) and not re.search(rule.get("exclude", r"$^"), name, re.IGNORECASE):
            return ingredient
    return None


def clean_name(name):
    name = re.sub(r"\s+", " ", name.replace("\u2011", "-").replace("\u202f", " ")).strip()
    name = re.sub(r"\b(\w+)(?: \1\b)+", r"\1", name, flags=re.IGNORECASE)  # "Spar Spar Cake" -> "Spar Cake"
    return name[:1].upper() + name[1:]
