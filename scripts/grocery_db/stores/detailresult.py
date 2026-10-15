"""Dirk and DekaMarkt (both Detailresult Groep): the offers embedded in their /aanbiedingen pages."""

from .. import dates, pagedata
from ..records import Offer


IMAGE_HOSTS = {
    "https://www.dirk.nl/aanbiedingen": "https://web-fileserver.dirk.nl/",
    "https://www.dekamarkt.nl/aanbiedingen": "https://web-fileserver.dekamarkt.nl/",
}
IMAGE_WIDTH = "?width=300"  # the originals are 1–3 MB PNGs; the file server resizes on request


def fetch_dirk(http):
    return parse_page(http.text("https://www.dirk.nl/aanbiedingen"), "https://www.dirk.nl/aanbiedingen")


def fetch_dekamarkt(http):
    return parse_page(http.text("https://www.dekamarkt.nl/aanbiedingen"), "https://www.dekamarkt.nl/aanbiedingen")


def _image(offer, products, page_url):
    """The first product's photo (offer banners aren't publicly readable), resized."""
    path = next((p["productInformation"]["image"] for p in products
                 if (p.get("productInformation") or {}).get("image")), None)
    if not path:
        return None
    if path.startswith("http"):
        return path
    return IMAGE_HOSTS[page_url] + path.lstrip("/") + IMAGE_WIDTH


def parse_page(html, page_url):
    data = pagedata.page_data(html)
    if data is None:
        raise ValueError(f"{page_url} has no embedded data")
    offers = {}
    for offer in pagedata.find_objects(data, ["offerId", "offerPrice", "startDate", "endDate"]):
        if not offer.get("offerPrice"):
            continue
        products = [p for p in offer.get("products") or [] if isinstance(p, dict)]
        regular = offer.get("normalPrice") or max((p.get("normalPrice") or 0 for p in products), default=0)
        sign = (offer.get("textPriceSign") or "").replace("_", " ").strip()
        if sign.lower() == "actie":  # a placeholder, not a deal
            sign = ""
        offers[str(offer["offerId"])] = Offer(
            key=str(offer["offerId"]),
            title=(offer.get("headerText") or "").strip(),
            # These sites write local calendar dates with a 'Z' suffix.
            valid_from=dates.local_start(dates.calendar_day(offer["startDate"])),
            valid_to=dates.end_of(offer["endDate"]),
            offer_price=float(offer["offerPrice"]),
            regular_price=float(regular) if regular and regular > offer["offerPrice"] else None,
            deal_text=sign or None,
            size=(offer.get("packaging") or offer.get("subText") or "").strip().rstrip("."),
            url=page_url,
            image_url=_image(offer, products, page_url),
        )
    return list(offers.values())
