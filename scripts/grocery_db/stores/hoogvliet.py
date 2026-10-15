"""Hoogvliet: the promotion periods embedded in hoogvliet.nl/aanbiedingen (each a week with its products)."""

from .. import dates, pagedata
from ..records import Offer

OFFERS_URL = "https://hoogvliet.nl/aanbiedingen"


def fetch_offers(http):
    return parse_page(http.text(OFFERS_URL))


def parse_page(html):
    data = pagedata.page_data(html)
    periods = (((data or {}).get("props") or {}).get("pageProps") or {}).get("promotionPeriods")
    if periods is None:
        raise ValueError("hoogvliet.nl offers page has no promotion periods")
    offers = {}
    for period in periods:
        valid_from = dates.local_start(dates.calendar_day(period["validFrom"]))
        valid_to = dates.local_end(dates.calendar_day(period["validTo"]))
        for group in period.get("groups") or []:
            for item in group.get("items") or []:
                meta = item.get("promotion_meta_data") or {}
                prices = (item.get("price_range") or {}).get("minimum_price") or {}
                price = (prices.get("final_price") or {}).get("value") or _number(meta.get("promotie_prijs"))
                if not price:
                    continue
                regular = (prices.get("regular_price") or {}).get("value") or _number(meta.get("prijs"))
                key = f"{item.get('sku') or item.get('id')}@{period.get('weekNr', '')}"
                offers[key] = Offer(
                    key=key,
                    title=(item.get("name") or meta.get("name") or "").strip(),
                    valid_from=valid_from,
                    valid_to=valid_to,
                    offer_price=float(price),
                    regular_price=float(regular) if regular and regular > price else None,
                    deal_text=meta.get("korting_label") or None,
                    size=(meta.get("promotie_beschrijving") or "").strip(),
                    category=group.get("name"),
                    url=f"https://hoogvliet.nl/product/{item['url_key']}" if item.get("url_key") else OFFERS_URL,
                )
    return list(offers.values())


def _number(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
