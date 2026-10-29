"""Open Prices (prices.openfoodfacts.org): prices that shoppers photograph on shelf tags and receipts, published by
Open Food Facts as open data under the Open Database License (ODbL). It is the only source of store prices: no
supermarket website is read, so the data is free to use and share with the attribution
"Price data © Open Food Facts contributors, ODbL" (shown in the app and in the published feed).

For each chain, its Dutch stores' prices from the last weeks become:
- offers: discounted prices, as offers for the Monday-to-Sunday week they were seen in;
- shelf prices: the latest regular price of each product, for the grocery list's ingredient prices.

The data is crowdsourced, so there are only a few prices per chain. Product photos (Open Food Facts images, under
their own CC BY-SA licence) are not used.
"""

import datetime as dt
import urllib.parse

from .. import dates
from ..records import Offer, Product

API = "https://prices.openfoodfacts.org/api/v1"
USER_AGENT = "SmartMealPlanner/1.0 (github.com/nivedhitha97/SmartMealPlanner)"
OFFER_DAYS = 7           # discounts seen this long ago or less are current offers
SHELF_PRICE_DAYS = 90    # regular prices seen this long ago or less count as current shelf prices
MAX_PAGES = 10
IDS_PER_REQUEST = 50
ATTRIBUTION = "Price data © Open Food Facts contributors, ODbL"
LICENSE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"


def fetch(http, chain, today=None):
    """(offers, shelf prices) for the chain's Dutch stores."""
    today = today or dt.datetime.now(dates.AMSTERDAM).date()
    ids = location_ids(http, chain)
    if not ids:
        return [], []
    since = (today - dt.timedelta(days=SHELF_PRICE_DAYS)).isoformat()
    offer_since = today - dt.timedelta(days=OFFER_DAYS)
    offers, products = {}, {}
    for start in range(0, len(ids), IDS_PER_REQUEST):
        chunk = ",".join(str(i) for i in ids[start:start + IDS_PER_REQUEST])
        for item in _pages(http, "prices", {"location_id__in": chunk, "date__gte": since, "order_by": "-date"}):
            if item.get("price_is_discounted"):
                if (item.get("date") or "")[:10] >= offer_since.isoformat():
                    offer = parse_price(item)
                    if offer and offer.key not in offers:  # newest first: keep the latest sighting
                        offers[offer.key] = offer
            else:
                product = parse_shelf_price(item)
                if product and product.key not in products:
                    products[product.key] = product
    return list(offers.values()), list(products.values())


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


def _usable(item):
    return item.get("price") is not None and item.get("date") and (item.get("currency") or "EUR") == "EUR"


def _name(item):
    product = item.get("product") or {}
    return product.get("product_name") or _category_name(item.get("category_tag"))


def _key(item):
    return item.get("product_code") or item.get("category_tag") or str(item["id"])


def _size(item):
    return "1 kg" if item.get("price_per") == "KILOGRAM" else ((item.get("product") or {}).get("quantity") or "")


def _url(item):
    return f"https://prices.openfoodfacts.org/prices/{item['id']}" if item.get("id") else None


def parse_price(item):
    """A discounted price as an offer for the Monday-to-Sunday week it was seen in; None if unusable."""
    name = _name(item)
    if not _usable(item) or not name:
        return None
    price = float(item["price"])
    seen = dt.date.fromisoformat(item["date"][:10])
    monday = seen - dt.timedelta(days=seen.weekday())
    regular = item.get("price_without_discount")
    return Offer(
        key=_key(item),
        title=name,
        valid_from=dates.local_start(monday),
        valid_to=dates.local_end(monday + dt.timedelta(days=6)),
        offer_price=price,
        regular_price=float(regular) if regular and float(regular) > price else None,
        deal_text=_deal(item.get("discount_type")),
        size=_size(item),
        url=_url(item),
    )


def parse_shelf_price(item):
    """A regular (not discounted) price as a product's shelf price; None if unusable."""
    name = _name(item)
    if not _usable(item) or not name or float(item["price"]) <= 0:
        return None
    return Product(key=_key(item), name=name, price=float(item["price"]), size=_size(item), url=_url(item))


def _category_name(tag):
    """'en:apples' → 'Apples' for loose produce priced without a barcode."""
    if not tag:
        return None
    return tag.split(":", 1)[-1].replace("-", " ").capitalize()


def _deal(discount_type):
    return {"QUANTITY": "Meer voor minder", "LOYALTY_PROGRAM": "Met klantenkaart",
            "EXPIRES_SOON": "Bijna houdbaar"}.get(discount_type or "", "Korting")
