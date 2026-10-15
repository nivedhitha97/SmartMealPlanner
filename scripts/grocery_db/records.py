"""What the store fetchers return."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class Offer:
    """A promotion with the dates the store gives for it."""
    key: str                      # the store's own id for the offer
    title: str
    valid_from: str               # ISO 8601 with offset, e.g. 2026-10-14T00:00:00+02:00
    valid_to: str
    offer_price: Optional[float] = None
    regular_price: Optional[float] = None
    deal_text: Optional[str] = None   # "1+1 gratis", "2 voor 5,00", "25% korting"
    size: str = ""
    category: Optional[str] = None
    url: Optional[str] = None


@dataclass
class Product:
    """A catalog product and its current shelf price."""
    key: str
    name: str
    price: float
    size: str = ""
    url: Optional[str] = None
