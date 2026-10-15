"""Writes the files the app downloads from the database: offers.json, prices.json and meta.json."""

import datetime as dt
import json
import re
import statistics
import uuid

from . import dates, schedule
from .db import utc
from .matching import INGREDIENTS, NON_FOOD, category_for, clean_name, grams, ingredient_for, short_size

FRESH_DAYS = 45          # shelf prices unchanged for longer than this are treated as stale
DROP_WINDOW_DAYS = 21    # price drops: compared with the highest price in this window
MIN_DROP_RATIO, MIN_DROP_EUROS = 0.10, 0.20
MAX_PRICE_DROPS = 40

_STOP_WORDS = {"alle", "jumbo", "en", "of", "met", "de", "het", "een", "van", "voor", "per", "pak", "pakken"}


def export(db, now, out_dir, requests_this_run):
    stores = {row["id"]: row for row in db.stores()}
    fresh = [sid for sid, row in stores.items() if row["has_catalog"] and _is_fresh(row, now)]

    offers = store_offers(db, stores, fresh, now) + price_drops(db, stores, fresh, now)
    offers.sort(key=lambda o: (o["ingredientName"] is None, o["validUntil"], -_saving(o)))
    prices = ingredient_prices(db, stores, fresh)
    meta = {
        "generatedAt": utc(now),
        "nextUpdateAt": min((s["nextUpdateAt"] for s in _store_meta(stores, now)), default=None),
        "source": "SmartMealPlanner grocery database (store websites and Checkjebon)",
        "offerCount": len(offers),
        "priceCount": len(prices),
        "productCount": db.connection.execute("SELECT count(*) FROM products").fetchone()[0],
        "requests": {
            "thisRun": requests_this_run,
            "last7Days": db.requests_since(utc(now - dt.timedelta(days=7))),
            "last28Days": db.requests_since(utc(now - dt.timedelta(days=28))),
        },
        "stores": _store_meta(stores, now),
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, value in (("offers.json", offers), ("prices.json", prices), ("meta.json", meta)):
        (out_dir / name).write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return meta


# ---- Offers ----

def store_offers(db, stores, fresh, now):
    """Offers fetched from the stores themselves that are valid now. Deals without a price (Jumbo's
    '1+1 gratis') are priced from the shelf price of the cheapest product they apply to."""
    catalogs = {}
    result = []
    for row in db.current_offers(now):
        title = clean_name(row["title"])
        if NON_FOOD.search(f"{title} {row['size'] or ''} {row['category'] or ''}"):
            continue
        deal = clean_deal(row["deal_text"])
        price, regular = per_item(row["offer_price"], row["regular_price"], deal)
        size = row["size"] or ""
        if price is None:
            if row["store_id"] not in fresh:
                continue
            if row["store_id"] not in catalogs:
                catalogs[row["store_id"]] = _word_index(db.catalog(row["store_id"]))
            product = _cheapest_match(title, size, catalogs[row["store_id"]])
            price = deal_price(deal, product["price"]) if product else None
            if price is None:
                continue
            regular, size = product["price"], size or product["size"] or ""
        result.append(_offer_json(
            key=f"{row['store_id']}:{row['offer_key']}:{row['valid_from']}",
            store=stores[row["store_id"]]["name"], title=title, price=price, regular=regular, size=size,
            valid_until=row["valid_to"], deal=_deal_label(deal, row["offer_price"]), category=row["category"],
            image_url=row["image_url"]))
    return result


def clean_deal(text):
    """The deal in a consistent form ('1 + 1 Gratis' → '1+1 gratis'), or None for text that only describes
    the unit or price ('per stuk 1,99', '500 gram', 'bij 12.50 gratis bezorging')."""
    if not text:
        return None
    deal = re.sub(r"\s*\+\s*", "+", re.sub(r"\s+", " ", text.strip().lower()))
    if re.match(r"^(per|bij)\b", deal) or re.fullmatch(r"[\d.,]+\s*(gram|g|kg|kilo|ml|liter|l|stuks?)", deal):
        return None
    return deal.replace("lidl plus", "Lidl Plus")


def _bundle_size(deal):
    """How many items a deal's price covers: '2 voor …' → 2, '1+2 gratis' → 3, '2e halve prijs' → 2."""
    if not deal:
        return 1
    match = re.search(r"(\d+)\+(\d+)\s*gratis", deal)
    if match:
        return int(match[1]) + int(match[2])
    match = re.match(r"(\d+)\s*voor\b", deal) or re.match(r"(\d+)e\s*(halve\s*prijs|gratis)", deal)
    return int(match[1]) if match else 1


def per_item(price, regular, deal):
    """(price, regular price) per item. Stores give multi-buy deals as the bundle total ('2 voor 4,99';
    '1+1 gratis' at 1,49 with a regular 2,98); without a regular price, 'a+b gratis' means the price is per item."""
    if price is None:
        return None, regular
    count = _bundle_size(deal)
    if count == 1:
        return price, regular
    free = re.search(r"(\d+)\+(\d+)\s*gratis", deal or "")
    if free and not regular:  # price per item, and you pay for only `a` of every a+b
        return round(price * int(free[1]) / count, 2), price
    return round(price / count, 2), round(regular / count, 2) if regular else None


def _deal_label(deal, bundle_price):
    """'2 voor' on its own gets its price: '2 voor €5,00'."""
    if deal and re.fullmatch(r"\d+\s*voor", deal) and bundle_price:
        return f"{deal} €{bundle_price:.2f}".replace(".", ",")
    return deal


def price_drops(db, stores, fresh, now):
    """For stores without an offers fetcher: products clearly cheaper than they were in the last three weeks."""
    since = utc(now - dt.timedelta(days=DROP_WINDOW_DAYS))
    drops = []
    for store_id in fresh:
        if stores[store_id]["has_offers"]:
            continue
        for product in db.connection.execute(
                "SELECT * FROM products WHERE store_id = ? AND price_since >= ?", (store_id, since)):
            highest = db.highest_recent_price(store_id, product["product_key"], since)
            name = clean_name(product["name"])
            if not highest or NON_FOOD.search(name):
                continue
            drop = highest - product["price"]
            if drop >= MIN_DROP_EUROS and MIN_DROP_RATIO <= drop / highest <= 0.7:
                seen = dates.parse(product["price_since"])
                drops.append(_offer_json(
                    key=f"{store_id}:{product['product_key']}:{product['price_since']}",
                    store=stores[store_id]["name"], title=name, price=product["price"], regular=highest,
                    size=product["size"] or "", valid_until=utc(seen + dt.timedelta(days=7)), deal=None,
                    category=None, observed_at=product["price_since"]))
    drops.sort(key=lambda o: (o["ingredientName"] is None, -_saving(o)))
    return drops[:MAX_PRICE_DROPS]


def deal_price(deal, regular):
    """Price per item under a deal, from the regular price: '1+1 gratis' → half, '2 voor 5,00' → 2.50."""
    if not deal or not regular:
        return None
    text = deal.lower().replace(",", ".")
    patterns = [
        (r"(\d+)\s*\+\s*(\d+)\s*gratis", lambda m: regular * int(m[1]) / (int(m[1]) + int(m[2]))),
        (r"(\d+)e\s*halve\s*prijs", lambda m: regular * (int(m[1]) - 0.5) / int(m[1])),
        (r"(\d+)e\s*gratis", lambda m: regular * (int(m[1]) - 1) / int(m[1])),
        (r"(\d+)\s*voor\s*€?\s*(\d+(?:\.\d{1,2})?)", lambda m: float(m[2]) / int(m[1])),
        (r"(\d+)\s*%\s*korting", lambda m: regular * (1 - int(m[1]) / 100)),
        (r"-\s*(\d+)\s*%", lambda m: regular * (1 - int(m[1]) / 100)),
        (r"voor\s*€?\s*(\d+(?:\.\d{1,2})?)", lambda m: float(m[1])),
    ]
    for pattern, price in patterns:
        match = re.search(pattern, text)
        if match:
            value = round(price(match), 2)
            return value if 0 < value < regular else None
    return None


def _word_index(products):
    index = {}
    for product in products:
        for word in set(_words(product["name"])):
            index.setdefault(word, []).append(product)
    return index


def _words(text):
    return [w for w in re.findall(r"[a-zà-ÿ0-9]+", text.lower()) if len(w) > 2 and w not in _STOP_WORDS]


def _cheapest_match(title, size, index):
    """The cheapest product whose name contains every significant word of the promotion title."""
    words = _words(title)
    if not words:
        return None
    candidates = None
    for word in words:
        matches = {id(p): p for p in index.get(word, [])}
        candidates = matches if candidates is None else {k: v for k, v in candidates.items() if k in matches}
        if not candidates:
            return None
    return min(candidates.values(), key=lambda p: p["price"])


def _offer_json(key, store, title, price, regular, size, valid_until, deal, category, observed_at=None,
                image_url=None):
    return {
        "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"smartmealplanner:{key}")).upper(),
        "storeName": store,
        "productName": title,
        "category": _category(title, category),
        "offerPrice": round(price, 2),
        "regularPrice": round(regular, 2) if regular and regular > price else None,
        "unitLabel": unit_label(size),
        "validUntil": valid_until,
        "observedAt": observed_at,
        "regionId": "NL",
        "notes": deal,
        "dealText": deal,
        "ingredientName": ingredient_for(title),
        "imageURL": image_url,
    }


def unit_label(size):
    """A short pack size for 'per …' ('500 g', 'pak 1 l'), or 'item' when the store's text is a description
    ('Alle soorten', 'Bij 12,50 gratis bezorging')."""
    label = short_size(size or "").strip().rstrip(".")
    if not re.search(r"\d", label) or len(label) > 24 or re.search(r"bezorg|soorten|o\.a\.|bijv", label, re.I):
        return "item"
    return label


def _category(title, store_category):
    """Category from the product name, else from the store's own category name."""
    category = category_for(title)
    return category_for(store_category) if category == "Groceries" and store_category else category


def _saving(offer):
    return (offer["regularPrice"] or offer["offerPrice"]) - offer["offerPrice"]


# ---- Ingredient prices ----

def ingredient_prices(db, stores, fresh):
    """Typical price per 100 g of every recipe ingredient across stores with current shelf prices."""
    per_ingredient = {name: [] for name in INGREDIENTS}
    for store_id in fresh:
        for product in db.catalog(store_id):
            name = clean_name(product["name"])
            ingredient = ingredient_for(name)
            if not ingredient or product["price"] < 0.25:  # a few cents is a data error
                continue
            weight = grams(product["size"] or "", name, INGREDIENTS[ingredient].get("pieceGrams"))
            if not weight or not 20 <= weight <= 5000:
                continue
            per_ingredient[ingredient].append({
                "store": stores[store_id]["name"], "product": name, "price": product["price"],
                "size": product["size"] or "", "per100g": product["price"] / weight * 100,
            })
    prices = []
    for ingredient, products in per_ingredient.items():
        if not products:
            continue
        by_store = {}
        for p in products:
            if p["store"] not in by_store or p["per100g"] < by_store[p["store"]]["per100g"]:
                by_store[p["store"]] = p
        cheapest = min(by_store.values(), key=lambda p: p["per100g"])
        prices.append({
            "ingredientName": ingredient,
            "pricePer100g": round(statistics.median(p["per100g"] for p in by_store.values()), 3),
            "cheapestStore": cheapest["store"],
            "cheapestProduct": cheapest["product"],
            "cheapestPrice": cheapest["price"],
            "cheapestSize": cheapest["size"],
            "cheapestPricePer100g": round(cheapest["per100g"], 3),
            "storeCount": len(by_store),
            "productCount": len(products),
        })
    return sorted(prices, key=lambda p: p["ingredientName"])


# ---- Store schedule ----

def _is_fresh(row, now):
    changed = row["catalog_changed_at"]
    return bool(changed) and now - dates.parse(changed) <= dt.timedelta(days=FRESH_DAYS)


def _store_meta(stores, now):
    result = []
    for row in stores.values():
        result.append({
            "id": row["id"],
            "name": row["name"],
            "updateDay": dates.WEEKDAYS[schedule.weekday_of(row)],
            "updateDaySource": "manual" if row["manual_update_weekday"] is not None else row["weekday_source"],
            "note": row["weekday_note"],
            "fetchesOffers": bool(row["has_offers"]),
            "lastUpdatedAt": row["last_success_at"],
            "nextUpdateAt": utc(schedule.next_fetch(schedule.weekday_of(row), row["fetched_week"], now)),
            "pricesChangedAt": row["catalog_changed_at"],
            "pricesAreCurrent": _is_fresh(row, now) if row["has_catalog"] else None,
            "lastError": row["last_error"],
        })
    return sorted(result, key=lambda s: s["name"])
