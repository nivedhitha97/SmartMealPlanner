"""Lidl: the weekly in-store offers from the lidl.nl search API ('Eten & drinken'). Lidl has no online
grocery assortment, so these offers are all there is."""

from .. import dates
from ..records import Offer

FOOD_URL = ("https://www.lidl.nl/q/api/search?assortment=NL&locale=nl_NL&version=v2.0.0&q="
            "&category.id=10068374&fetchsize=60&offset={offset}")
MAX_ITEMS = 600


def fetch_offers(http):
    offers, offset = [], 0
    while offset < MAX_ITEMS:
        page = http.json(FOOD_URL.format(offset=offset))
        items = page.get("items") or []
        offers.extend(offer for offer in map(parse_item, items) if offer)
        offset += len(items)
        if not items or offset >= page.get("numFound", 0):
            break
    return offers


def parse_item(item):
    data = (item.get("gridbox") or {}).get("data") or {}
    start, end = data.get("storeStartDate"), data.get("storeEndDate")
    price_info = data.get("price") or {}
    price, deal = price_info.get("price"), None
    lidl_plus = ((data.get("lidlPlus") or [{}])[0].get("price") or {}).get("price")
    if price is None and lidl_plus is not None:
        price, deal = lidl_plus, "met Lidl Plus"
    if not start or not end or price is None:
        return None
    discount = price_info.get("discount") or {}
    regular = price_info.get("oldPrice") or discount.get("deletedPrice")
    if discount.get("percentageDiscount"):
        deal = f"-{discount['percentageDiscount']}%" + (f" {deal}" if deal else "")
    path = data.get("canonicalUrl") or data.get("canonicalPath") or ""
    return Offer(
        key=str(data.get("productId") or data.get("itemId") or data.get("erpNumber")),
        title=data.get("fullTitle") or data.get("title") or "",
        valid_from=dates.from_epoch(start),
        valid_to=dates.from_epoch(end),
        offer_price=float(price),
        regular_price=float(regular) if regular else None,
        deal_text=deal,
        size=(price_info.get("packaging") or {}).get("text") or "",
        url=("https://www.lidl.nl" + path) if path.startswith("/") else (path or None),
        image_url=data.get("image") or next(iter(data.get("imageList") or []), None),
    )
