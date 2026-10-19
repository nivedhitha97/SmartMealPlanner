"""Open Prices (prices.openfoodfacts.org): prices that shoppers photograph on shelf tags and receipts, published
as open data under the ODbL. It is the free and legal source for Albert Heijn, which blocks automated requests
to its own site: discounted prices seen in AH stores become AH offers for the Bonus week they were seen in
(AH's Bonus week runs Monday to Sunday).

The data is crowdsourced, so there are only a few AH discounts a week; it adds to, never replaces, the
shelf prices from Checkjebon. Attribution: "Price data © Open Food Facts contributors, ODbL".
"""

import datetime as dt
import urllib.parse

from .. import dates
from ..records import Offer

API = "https://prices.openfoodfacts.org/api/v1"
USER_AGENT = "SmartMealPlanner/1.0 (github.com/nivedhitha97/SmartMealPlanner)"
LOOKBACK_DAYS = 7
MAX_PAGES = 10
IDS_PER_REQUEST = 50


def fetch_ah_offers(http, today=None):
    """AH discounts seen in the last week, as offers."""
    return fetch_offers(http, "Albert Heijn", today=today)


def fetch_offers(http, chain, today=None):
    today = today or dt.datetime.now(dates.AMSTERDAM).date()
    ids = location_ids(http, chain)
    since = (today - dt.timedelta(days=LOOKBACK_DAYS)).isoformat()
    offers = {}
    for start in range(0, len(ids), IDS_PER_REQUEST):
        chunk = ",".join(str(i) for i in ids[start:start + IDS_PER_REQUEST])
        for item in _pages(http, "prices", {"location_id__in": chunk, "price_is_discounted": "true",
                                             "date__gte": since, "order_by": "-date"}):
            offer = parse_price(item)
            if offer and offer.key not in offers:  # newest first: keep the latest sighting of each product
                offers[offer.key] = offer
    return list(offers.values())


def location_ids(http, chain):
    """Open Prices locations of a chain in the Netherlands that have prices."""
    items = _pages(http, "locations", {"osm_name__like": chain, "osm_address_country__like": "Nederland",
                                        "price_count__gte": 1})
    return [item["id"] for item in items if _is_chain(item.get("osm_name") or "", chain)]


def _is_chain(name, chain):
    """'Albert Heijn' and 'Albert Heijn XL', not a café that happens to mention it."""
    return name.lower().startswith(chain.lower())


def _pages(http, path, query):
    for page in range(1, MAX_PAGES + 1):
        url = f"{API}/{path}?" + urllib.parse.urlencode({**query, "page": page, "size": 100})
        data = http.json(url, headers={"User-Agent": USER_AGENT})
        yield from data.get("items") or []
        if page >= (data.get("pages") or 1):
            return


def parse_price(item):
    """A discounted price as an offer for the Monday-to-Sunday week it was seen in; None if unusable."""
    price, day = item.get("price"), item.get("date")
    if price is None or not day or (item.get("currency") or "EUR") != "EUR":
        return None
    product = item.get("product") or {}
    name = product.get("product_name") or _category_name(item.get("category_tag"))
    if not name:
        return None
    seen = dt.date.fromisoformat(day[:10])
    monday = seen - dt.timedelta(days=seen.weekday())
    per_kilo = item.get("price_per") == "KILOGRAM"
    regular = item.get("price_without_discount")
    return Offer(
        key=item.get("product_code") or item.get("category_tag") or str(item["id"]),
        title=name,
        valid_from=dates.local_start(monday),
        valid_to=dates.local_end(monday + dt.timedelta(days=6)),
        offer_price=float(price),
        regular_price=float(regular) if regular and float(regular) > float(price) else None,
        deal_text=_deal(item.get("discount_type")),
        size="1 kg" if per_kilo else (product.get("quantity") or ""),
        url=f"https://prices.openfoodfacts.org/prices/{item['id']}" if item.get("id") else None,
        image_url=product.get("image_url"),
    )


def _category_name(tag):
    """'en:apples' → 'Apples' for loose produce priced without a barcode."""
    if not tag:
        return None
    return tag.split(":", 1)[-1].replace("-", " ").capitalize()


def _deal(discount_type):
    return {"QUANTITY": "Bonus (meer voor minder)", "LOYALTY_PROGRAM": "Bonus met Bonuskaart",
            "EXPIRES_SOON": "Bijna houdbaar"}.get(discount_type or "", "Bonus")
