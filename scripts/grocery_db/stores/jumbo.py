"""Jumbo: the promotions on jumbo.com/aanbiedingen/nu, with their exact start and end times.

Jumbo's promotions describe a deal ("1+1 gratis", "2 voor 5,00") rather than a price; the price is worked
out later from the deal and the product's shelf price (see export.deal_price)."""

from .. import pagedata
from ..records import Offer

OFFERS_URL = "https://www.jumbo.com/aanbiedingen/nu"


def fetch_offers(http):
    return parse_page(http.text(OFFERS_URL))


def parse_page(html):
    data = pagedata.page_data(html)
    if data is None:
        raise ValueError("jumbo.com offers page has no embedded data")
    offers = {}
    for promo in pagedata.find_objects(data, ["isKiesAndMix", "start", "end", "title"]):
        start, end = (promo.get("start") or {}).get("iso"), (promo.get("end") or {}).get("iso")
        if not start or not end or promo.get("hidden") or not promo.get("id"):
            continue
        tags = [tag.get("text") for tag in promo.get("tags") or [] if tag.get("text")]
        url = promo.get("url")
        offers[str(promo["id"])] = Offer(
            key=str(promo["id"]),
            title=promo["title"],
            valid_from=start,
            valid_to=end,
            deal_text=", ".join(tags) or None,
            size=promo.get("subtitle") or "",
            url=("https://www.jumbo.com" + url) if url and url.startswith("/") else url,
            image_url=promo.get("image") or None,
        )
    return list(offers.values())
