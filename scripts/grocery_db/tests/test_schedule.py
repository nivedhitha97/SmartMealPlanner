import datetime as dt
import unittest

from grocery_db import dates, schedule
from grocery_db.records import Offer

WED = 2


def at(text):
    """An Amsterdam time: at('2026-10-14 07:00')."""
    return dt.datetime.fromisoformat(text).replace(tzinfo=dates.AMSTERDAM)


def offer(start):
    return Offer(key=start, title="x", valid_from=dates.local_start(dt.date.fromisoformat(start)),
                 valid_to=dates.local_end(dt.date.fromisoformat(start) + dt.timedelta(days=6)))


class WeekStartTests(unittest.TestCase):
    def test_on_the_update_day_after_the_fetch_hour_the_new_week_has_started(self):
        self.assertEqual(schedule.week_start(at("2026-10-14 07:00"), WED), dt.date(2026, 10, 14))

    def test_before_the_fetch_hour_it_is_still_last_week(self):
        self.assertEqual(schedule.week_start(at("2026-10-14 05:00"), WED), dt.date(2026, 10, 7))

    def test_later_in_the_week_it_is_the_most_recent_update_day(self):
        self.assertEqual(schedule.week_start(at("2026-10-18 12:00"), WED), dt.date(2026, 10, 14))

    def test_utc_times_are_read_in_amsterdam_time(self):
        # 04:30 UTC on Wednesday is 06:30 in Amsterdam (summer time), so the new week has started.
        self.assertEqual(schedule.week_start(dt.datetime(2026, 10, 14, 4, 30, tzinfo=dt.timezone.utc), WED),
                         dt.date(2026, 10, 14))


class DueTests(unittest.TestCase):
    def test_a_store_never_fetched_is_due(self):
        self.assertTrue(schedule.is_due(WED, None, None, 0, at("2026-10-16 07:00")))

    def test_a_store_fetched_this_week_is_not_due_until_its_next_update_day(self):
        for day in ("2026-10-15", "2026-10-18", "2026-10-20"):
            self.assertFalse(schedule.is_due(WED, "2026-10-14", "2026-10-14", 1, at(f"{day} 07:00")), day)
        self.assertTrue(schedule.is_due(WED, "2026-10-14", "2026-10-14", 1, at("2026-10-21 07:00")))

    def test_a_store_that_has_not_published_its_week_is_retried_up_to_the_limit(self):
        now = at("2026-10-15 07:00")
        self.assertTrue(schedule.is_due(WED, "2026-10-07", "2026-10-14", schedule.MAX_ATTEMPTS - 1, now))
        self.assertFalse(schedule.is_due(WED, "2026-10-07", "2026-10-14", schedule.MAX_ATTEMPTS, now))

    def test_attempts_from_an_earlier_week_do_not_count(self):
        self.assertTrue(schedule.is_due(WED, "2026-10-07", "2026-10-07", 5, at("2026-10-14 07:00")))

    def test_next_fetch_is_the_next_update_day_at_the_fetch_hour(self):
        nxt = schedule.next_fetch(WED, "2026-10-14", at("2026-10-16 12:00"))
        self.assertEqual(nxt, at(f"2026-10-21 {schedule.FETCH_HOUR:02d}:00"))

    def test_next_fetch_of_a_due_store_is_now(self):
        now = at("2026-10-16 12:00")
        self.assertEqual(schedule.next_fetch(WED, "2026-10-07", now), now)


class OfferWeekTests(unittest.TestCase):
    def test_new_week_is_published_when_an_offer_starts_this_week(self):
        now = at("2026-10-14 07:00")
        self.assertTrue(schedule.has_new_week([offer("2026-10-07"), offer("2026-10-14")], WED, now))
        self.assertFalse(schedule.has_new_week([offer("2026-10-07")], WED, now))

    def test_weekday_is_learned_from_where_most_offers_start(self):
        offers = [offer("2026-10-13")] * 12 + [offer("2026-10-15")] * 3
        self.assertEqual(schedule.learn_weekday(offers, at("2026-10-14 07:00")), 1)  # Tuesday

    def test_weekday_is_not_learned_from_too_few_or_mixed_offers(self):
        now = at("2026-10-14 07:00")
        self.assertIsNone(schedule.learn_weekday([offer("2026-10-13")] * 3, now))
        mixed = [offer("2026-10-12")] * 5 + [offer("2026-10-13")] * 5 + [offer("2026-10-14")] * 5
        self.assertIsNone(schedule.learn_weekday(mixed, now))

    def test_long_running_offers_do_not_decide_the_weekday(self):
        offers = [offer("2026-01-07")] * 30 + [offer("2026-10-14")] * 12
        self.assertEqual(schedule.learn_weekday(offers, at("2026-10-14 07:00")), WED)


if __name__ == "__main__":
    unittest.main()
