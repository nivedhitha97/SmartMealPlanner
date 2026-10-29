"""When the data is fetched, and each store's offer week.

Open Prices is checked once a day, from FETCH_HOUR Amsterdam time (the workflow runs every morning). Each store's
offer-week day (configured, or set by hand in Supabase) is only used to tell the app when its new offers start.
"""

import datetime as dt

from . import dates

FETCH_HOUR = 6


def weekday_of(store_row):
    """The store's offer-week day: a manual choice (set in Supabase) wins over the configured one."""
    manual = store_row["manual_update_weekday"] if "manual_update_weekday" in store_row.keys() else None
    return manual if manual is not None else store_row["update_weekday"]


def next_fetch(now):
    """When the data is next fetched (an aware datetime): today at FETCH_HOUR if that's still ahead, else tomorrow."""
    local = now.astimezone(dates.AMSTERDAM)
    moment = dt.datetime.combine(local.date(), dt.time(FETCH_HOUR), dates.AMSTERDAM)
    return moment if moment > local else moment + dt.timedelta(days=1)
