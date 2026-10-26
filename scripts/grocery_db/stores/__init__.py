"""The supermarkets and the day of the week each starts its offer week.

No supermarket website is read: every chain's offers and shelf prices come from Open Prices (shopper-reported
open data, see openprices.py), checked once a day. The offer-week days are public facts, used by the app's offer
alerts and the Store updates list.
"""

from dataclasses import dataclass

MON, TUE, WED, THU, FRI, SAT, SUN = range(7)


@dataclass(frozen=True)
class Store:
    id: str
    name: str
    update_weekday: int
    weekday_note: str
    open_prices_name: str = ""   # the chain's name on OpenStreetMap, as Open Prices locations use it

    @property
    def osm_name(self):
        return self.open_prices_name or self.name


STORES = [
    Store("ah", "Albert Heijn", MON, "Bonus week runs Monday to Sunday"),
    Store("aldi", "Aldi", MON, "Offers run Monday to Sunday"),
    Store("dekamarkt", "DekaMarkt", TUE, "Offers run Tuesday to Monday"),
    Store("dirk", "Dirk", WED, "Offers run Wednesday to Tuesday"),
    Store("hoogvliet", "Hoogvliet", WED, "Offers run Wednesday to Tuesday"),
    Store("jumbo", "Jumbo", WED, "Offers run Wednesday to Tuesday"),
    Store("lidl", "Lidl", MON, "Offers run Monday to Sunday"),
    Store("plus", "Plus", MON, "Offers run Monday to Sunday"),
    Store("poiesz", "Poiesz", SUN, "Offers run Sunday to Saturday"),
    Store("spar", "Spar", MON, "Offers run Monday to Sunday"),
    Store("vomar", "Vomar", SUN, "Folder starts on Sunday"),
]

BY_ID = {store.id: store for store in STORES}
