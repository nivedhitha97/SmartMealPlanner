"""Poiesz: the offers embedded in the Poiesz web shop's /aanbiedingen page."""

from .. import dates, pagedata
from ..records import Offer

OFFERS_URL = "https://webwinkel.poiesz-supermarkten.nl/aanbiedingen"
FILES_URL = "https://files.poiesz-supermarkten.nl/"


def fetch_offers(http):
    return parse_page(http.text(OFFERS_URL))


def parse_page(html):
    data = pagedata.page_data(html)
    if data is None:
        raise ValueError("Poiesz offers page has no embedded data")
    offers = {}
    for offer in pagedata.find_objects(data, ["commercialTextLine1", "validFrom", "validUntil"]):
        products = [p for p in offer.get("overviewProducts") or [] if isinstance(p, dict)]
        first = products[0] if products else {}
        price = offer.get("newPriceLow") or first.get("price")
        if not price:
            continue
        regular = offer.get("oldPriceLow") or first.get("strikeThroughPrice")
        deal = " ".join(str(offer[k]) for k in ("offerTypeLine1", "offerTypeLine2", "offerTypeLine3") if offer.get(k))
        title = " ".join(str(offer[k]) for k in ("commercialTextLine1", "commercialTextLine2") if offer.get(k))
        offers[str(offer.get("id"))] = Offer(
            key=str(offer.get("id")),
            title=title.strip(),
            valid_from=dates.local_start(dates.calendar_day(offer["validFrom"])),
            valid_to=dates.end_of(offer["validUntil"]),
            offer_price=float(price),
            regular_price=float(regular) if regular and regular > price else None,
            deal_text=deal.lower() or None,
            size=(offer.get("commercialTextDetailsLine2") or first.get("packageDescription") or "").strip(),
            url=OFFERS_URL,
            image_url=_image(offer, first),
        )
    return list(offers.values())


def _image(offer, first_product):
    """The offer's own picture (a Photoshop file the file server converts and resizes), else the first
    product's photo."""
    if offer.get("imageFile"):
        return FILES_URL + offer["imageFile"].replace("\\", "/") + "?width=300&mode=fill"
    return first_product.get("image") or None
