"""When each store is fetched.

A store is fetched once per offer week, on the day its week starts (from FETCH_HOUR, Amsterdam time). The
workflow runs every morning; on days when no store is due it only makes the small daily Open Prices check. If a store hasn't
published its new week yet, it is tried again the next morning, up to MAX_ATTEMPTS times.
"""

import collections
import datetime as dt

from . import dates

FETCH_HOUR = 6
MAX_ATTEMPTS = 3
MIN_OFFERS_TO_LEARN = 10


def weekday_of(store_row):
    """The store's update day: a manual choice (set in Supabase) wins over the configured or learned one."""
    manual = store_row["manual_update_weekday"] if "manual_update_weekday" in store_row.keys() else None
    return manual if manual is not None else store_row["update_weekday"]


def week_start(now, weekday):
    """The date the store's current offer week started."""
    local = now.astimezone(dates.AMSTERDAM)
    today = local.date() if local.hour >= FETCH_HOUR else local.date() - dt.timedelta(days=1)
    return today - dt.timedelta(days=(today.weekday() - weekday) % 7)


def is_due(weekday, fetched_week, attempts_week, attempts, now):
    """Whether to fetch now: this offer week hasn't been fetched and hasn't run out of attempts."""
    current = week_start(now, weekday).isoformat()
    if fetched_week is not None and fetched_week >= current:
        return False
    return attempts_week != current or attempts < MAX_ATTEMPTS


def next_fetch(weekday, fetched_week, now):
    """When the store will next be fetched (an aware datetime)."""
    current = week_start(now, weekday)
    day = current + dt.timedelta(days=7) if fetched_week and fetched_week >= current.isoformat() else current
    moment = dt.datetime.combine(day, dt.time(FETCH_HOUR), dates.AMSTERDAM)
    return max(moment, now.astimezone(dates.AMSTERDAM))


def has_new_week(offers, weekday, now):
    """Whether the fetched offers include ones starting this offer week (so the store has published it)."""
    start = week_start(now, weekday)
    return any(start <= dates.parse(o.valid_from).astimezone(dates.AMSTERDAM).date() < start + dt.timedelta(days=7)
               for o in offers)


def learn_weekday(offers, now):
    """The weekday most offers starting within a week of `now` begin on, or None if it isn't clear."""
    local_now = now.astimezone(dates.AMSTERDAM)
    days = collections.Counter()
    for offer in offers:
        start = dates.parse(offer.valid_from).astimezone(dates.AMSTERDAM)
        if abs((start - local_now).days) <= 7:
            days[start.weekday()] += 1
    if sum(days.values()) < MIN_OFFERS_TO_LEARN:
        return None
    weekday, count = days.most_common(1)[0]
    return weekday if count * 2 > sum(days.values()) else None
