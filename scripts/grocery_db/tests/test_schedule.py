import datetime as dt
import unittest

from grocery_db import dates, schedule


def at(text):
    """An Amsterdam time: at('2026-10-14 07:00')."""
    return dt.datetime.fromisoformat(text).replace(tzinfo=dates.AMSTERDAM)


class NextFetchTests(unittest.TestCase):
    def test_before_the_fetch_hour_the_next_fetch_is_today(self):
        self.assertEqual(schedule.next_fetch(at("2026-10-14 05:00")), at("2026-10-14 06:00"))

    def test_after_the_fetch_hour_it_is_tomorrow(self):
        self.assertEqual(schedule.next_fetch(at("2026-10-14 07:00")), at("2026-10-15 06:00"))

    def test_utc_times_are_read_in_amsterdam_time(self):
        utc = dt.datetime(2026, 10, 14, 3, 30, tzinfo=dt.timezone.utc)  # 05:30 in Amsterdam
        self.assertEqual(schedule.next_fetch(utc), at("2026-10-14 06:00"))


class WeekdayTests(unittest.TestCase):
    def test_a_manual_weekday_wins(self):
        row = {"update_weekday": 2, "manual_update_weekday": 4}

        class Row(dict):
            def keys(self):
                return super().keys()

        self.assertEqual(schedule.weekday_of(Row(row)), 4)
        self.assertEqual(schedule.weekday_of(Row({**row, "manual_update_weekday": None})), 2)
