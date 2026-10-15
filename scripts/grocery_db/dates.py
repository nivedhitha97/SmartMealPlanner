"""Dates in the supermarkets' own time zone."""

import datetime as dt
from zoneinfo import ZoneInfo

AMSTERDAM = ZoneInfo("Europe/Amsterdam")
WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def local_start(day):
    """00:00 on a date in Amsterdam, as ISO 8601."""
    return dt.datetime.combine(day, dt.time(0, 0), AMSTERDAM).isoformat()


def local_end(day):
    """23:59:59 on a date in Amsterdam, as ISO 8601."""
    return dt.datetime.combine(day, dt.time(23, 59, 59), AMSTERDAM).isoformat()


def from_epoch(seconds):
    return dt.datetime.fromtimestamp(seconds, AMSTERDAM).isoformat()


def parse(value):
    """An aware datetime from an ISO 8601 string (assumed Amsterdam time if it has no offset)."""
    moment = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return moment if moment.tzinfo else moment.replace(tzinfo=AMSTERDAM)


def calendar_day(value):
    """The date written in a timestamp, ignoring its offset: '2026-10-14T00:00:00.000Z' → 14 October.
    Several stores write local dates with a 'Z' suffix."""
    return dt.date.fromisoformat(value[:10])


def end_of(value):
    """Inclusive end for a store's end timestamp: midnight means the day before ended, anything else that day."""
    day = calendar_day(value)
    time_part = value[11:19] if len(value) >= 19 else "00:00:00"
    if time_part == "00:00:00":
        day -= dt.timedelta(days=1)
    return local_end(day)
