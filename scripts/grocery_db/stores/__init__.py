"""The supermarkets, how each is fetched, and the day of the week each starts its offer week.

`update_weekday` is the starting point; after every offers fetch it is re-learned from the offers' own start
dates (see schedule.learn_weekday), so a store that moves its offer week is followed automatically.
"""

from dataclasses import dataclass
from typing import Callable, Optional

from . import detailresult, hoogvliet, jumbo, lidl, poiesz

MON, TUE, WED, THU, FRI, SAT, SUN = range(7)


@dataclass(frozen=True)
class Store:
    id: str
    name: str
    update_weekday: int
    weekday_note: str
    fetch_offers: Optional[Callable] = None   # web.Http -> [records.Offer]
    catalog: bool = True                       # shelf prices from Checkjebon


STORES = [
    Store("ah", "Albert Heijn", MON, "Bonus week runs Monday to Sunday (AH blocks automated requests, so "
          "only Checkjebon's catalog is used)"),
    Store("jumbo", "Jumbo", WED, "Offers run Wednesday to Tuesday (from jumbo.com promotion dates)",
          jumbo.fetch_offers),
    Store("lidl", "Lidl", MON, "Offers run Monday to Sunday (from lidl.nl offer dates)", lidl.fetch_offers),
    Store("dirk", "Dirk", WED, "Offers run Wednesday to Tuesday (from dirk.nl offer dates)",
          detailresult.fetch_dirk),
    Store("dekamarkt", "DekaMarkt", TUE, "Offers run Tuesday to Monday (from dekamarkt.nl offer dates)",
          detailresult.fetch_dekamarkt),
    Store("hoogvliet", "Hoogvliet", WED, "Offers run Wednesday to Tuesday (from hoogvliet.nl offer periods)",
          hoogvliet.fetch_offers),
    Store("poiesz", "Poiesz", SUN, "Offers run Sunday to Saturday (from the Poiesz web shop offer dates)",
          poiesz.fetch_offers),
    Store("plus", "Plus", MON, "Offer day not verified; checked weekly"),
    Store("spar", "Spar", MON, "Most catalog changes appear on Mondays"),
    Store("vomar", "Vomar", SUN, "Folder starts on Sunday"),
]

BY_ID = {store.id: store for store in STORES}
