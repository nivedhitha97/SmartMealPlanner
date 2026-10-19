"""Command line: python3 -m grocery_db update --data DIR   |   python3 -m grocery_db status --data DIR

Run from the scripts/ folder. `update` fetches only the stores whose offer week starts today (or that are still
waiting for their new week), saves everything to DIR/grocery.db and writes the app's files next to it.

With SUPABASE_URL and SUPABASE_SERVICE_KEY set, `update` also applies the manual edits made in Supabase and
mirrors new data there; `sync --full` sends the whole database (the first time, or to repair the mirror).
"""

import argparse
import datetime as dt
import os
import sys
import traceback
from pathlib import Path

from . import dates, export, schedule, supabase as mirror, web
from .db import Database, utc
from .stores import BY_ID, STORES, checkjebon

BASELINE_DAYS = 30  # first catalog import: compare with this long ago to see which stores are still updated


def main(argv=None):
    parser = argparse.ArgumentParser(prog="grocery_db", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["update", "status", "sync"])
    parser.add_argument("--data", type=Path, default=Path("../build/grocery-data"), help="folder with grocery.db")
    parser.add_argument("--store", action="append", default=[], help="fetch this store now, due or not")
    parser.add_argument("--all", action="store_true", help="fetch every store now")
    parser.add_argument("--now", help="pretend it is this time (ISO 8601), for testing the schedule")
    parser.add_argument("--full", action="store_true", help="sync: send every row, not just changes")
    parser.add_argument("--no-sync", action="store_true", help="update: don't talk to Supabase")
    args = parser.parse_args(argv)

    now = dates.parse(args.now) if args.now else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    args.data.mkdir(parents=True, exist_ok=True)
    db = Database(args.data / "grocery.db")
    db.sync_stores(STORES)
    try:
        if args.command == "status":
            print_status(db, now)
            return 0
        supabase = None if args.no_sync else mirror.Supabase.from_environment()
        if args.command == "sync":
            if not supabase:
                parser.error("set SUPABASE_URL and SUPABASE_SERVICE_KEY to sync")
            print("Sent to Supabase:", mirror.push(db, supabase, full=args.full))
            return 0
        forced = [s.id for s in STORES] if args.all else args.store
        unknown = [s for s in forced if s not in BY_ID]
        if unknown:
            parser.error(f"unknown store(s): {', '.join(unknown)}")
        # Manual edits first: a store's manual update day decides whether it is due.
        edits_changed = _sync(lambda: mirror.pull_overrides(db, supabase), "read manual edits") if supabase else False
        if edits_changed:
            print("Applied new manual edits from Supabase.")
        # A mirror that has never been filled is filled now, even on a day when no store is due.
        first_sync = bool(supabase) and db.sync_value("pushed_at") is None
        requests = update(db, now, forced)
        if requests is None and not edits_changed and not first_sync:
            print("No store is due today; nothing fetched.")
            _output("changed", "false")
            return 0
        if requests is None:
            print("No store is due today; nothing fetched." + (" Filling the Supabase mirror." if first_sync else ""))
        meta = export.export(db, now, args.data, requests or 0)
        if supabase:
            sent = _sync(lambda: mirror.push(db, supabase), "mirror the database")
            if sent:
                print("Sent to Supabase:", sent)
        print(f"Made {requests} requests. Exported {meta['offerCount']} offers and {meta['priceCount']} ingredient "
              f"prices; next update {meta['nextUpdateAt']}.")
        _output("changed", "true")
        return 0
    finally:
        db.close()


def update(db, now, forced=()):
    """Fetches due (or forced) stores. Returns the number of requests made, or None if nothing was due."""
    due = [row for row in db.stores()
           if row["id"] in forced or schedule.is_due(schedule.weekday_of(row), row["fetched_week"],
                                                     row["attempts_week"], row["attempts"], now)]
    daily_requests, daily_new = update_daily_offers(db, now)
    if not due:
        return daily_requests if daily_new else None
    now_s = utc(now)
    total = daily_requests
    print("Due: " + ", ".join(f"{row['name']} ({dates.WEEKDAYS[schedule.weekday_of(row)]})" for row in due))

    # Offers, from each store itself.
    succeeded = set()
    for row in due:
        store = BY_ID[row["id"]]
        if not store.fetch_offers:
            continue
        http, started = web.Http(), utc(dt.datetime.now(dt.timezone.utc))
        week = schedule.week_start(now, schedule.weekday_of(row)).isoformat()
        attempts = row["attempts"] + 1 if row["attempts_week"] == week else 1
        try:
            offers = store.fetch_offers(http)
            new = db.save_offers(store.id, offers, now_s)
            fresh_week = schedule.has_new_week(offers, schedule.weekday_of(row), now)
            learned = schedule.learn_weekday(offers, now)
            fields = {"attempts_week": week, "attempts": attempts, "last_fetch_at": now_s, "last_error": None}
            if fresh_week or attempts >= schedule.MAX_ATTEMPTS or store.id in forced:
                fields.update(fetched_week=week, last_success_at=now_s)
                succeeded.add(store.id)
            if learned is not None and learned != row["update_weekday"]:
                fields.update(update_weekday=learned, weekday_source="learned",
                              weekday_note=f"Learned from offer start dates on {now_s[:10]}")
            db.update_store(store.id, **fields)
            status = "ok" if fresh_week else "no-new-week"
            db.log_fetch(store.id, "offers", started, utc(dt.datetime.now(dt.timezone.utc)), status,
                         len(offers), http.requests)
            print(f"  {store.name}: {len(offers)} offers ({new} new), {http.requests} requests"
                  + ("" if fresh_week else " (new week not published yet; will retry)"))
        except Exception as error:  # one store failing must not stop the others
            db.update_store(store.id, attempts_week=week, attempts=attempts, last_fetch_at=now_s,
                            last_error=str(error)[:300])
            db.log_fetch(store.id, "offers", started, utc(dt.datetime.now(dt.timezone.utc)), "error",
                         requests=http.requests, message=str(error)[:300])
            print(f"  {store.name}: FAILED ({error})", file=sys.stderr)
            traceback.print_exc()
        total += http.requests

    # Shelf prices, from one shared Checkjebon download.
    catalog_stores = [row for row in due if BY_ID[row["id"]].catalog]
    if catalog_stores:
        total += update_catalogs(db, now, catalog_stores, succeeded)
    return total


def update_daily_offers(db, now):
    """Crowdsourced offers (Albert Heijn's, from Open Prices) arrive all week, so they are checked once a day
    whether the store is due or not. It is a couple of small requests and never touches the weekly schedule.
    Returns (requests made, new offers)."""
    today = now.astimezone(dates.AMSTERDAM).date().isoformat()
    requests = new = 0
    for row in db.stores():
        store = BY_ID[row["id"]]
        key = f"daily_offers:{store.id}"
        if not store.daily_offers or db.sync_value(key) == today:
            continue
        http, started = web.Http(), utc(dt.datetime.now(dt.timezone.utc))
        try:
            offers = store.daily_offers(http)
            added = db.save_offers(store.id, offers, utc(now))
            db.set_sync_value(key, today)
            db.log_fetch(store.id, "daily-offers", started, utc(dt.datetime.now(dt.timezone.utc)), "ok",
                         len(offers), http.requests)
            print(f"  {store.name} (Open Prices): {len(offers)} offers ({added} new), {http.requests} requests")
            new += added
        except Exception as error:  # crowdsourced extras must never stop the weekly fetch
            db.log_fetch(store.id, "daily-offers", started, utc(dt.datetime.now(dt.timezone.utc)), "error",
                         requests=http.requests, message=str(error)[:300])
            print(f"  {store.name} (Open Prices): FAILED ({error})", file=sys.stderr)
        requests += http.requests
    return requests, new


def update_catalogs(db, now, rows, offers_done):
    http, started, now_s = web.Http(), utc(dt.datetime.now(dt.timezone.utc)), utc(now)
    try:
        catalogs = checkjebon.fetch_catalogs(http)
    except Exception as error:
        db.log_fetch(None, "catalog", started, utc(dt.datetime.now(dt.timezone.utc)), "error",
                     requests=http.requests, message=str(error)[:300])
        print(f"  Checkjebon: FAILED ({error})", file=sys.stderr)
        return http.requests

    first_import = [row["id"] for row in rows if not db.has_catalog(row["id"])]
    baseline = None
    if first_import:  # without history, an older snapshot shows which stores are still being updated
        try:
            baseline = checkjebon.fetch_catalogs_at(http, now - dt.timedelta(days=BASELINE_DAYS),
                                                    token=os.environ.get("GITHUB_TOKEN"))
        except Exception as error:
            print(f"  Checkjebon history: FAILED ({error})", file=sys.stderr)

    for row in rows:
        products = catalogs.get(row["id"]) or []
        if not products:
            continue
        count, changed = db.save_catalog(row["id"], products, now_s)
        fields = {}
        if changed:
            fields["catalog_changed_at"] = now_s
        elif row["id"] in first_import and baseline is not None:
            old = {p.key: p.price for p in baseline.get(row["id"]) or []}
            moved = any(abs(old[p.key] - p.price) > 0.001 for p in products if p.key in old)
            # No change in a month: the source has stopped updating this store, so its prices count as stale.
            fields["catalog_changed_at"] = now_s if moved else None
        if not BY_ID[row["id"]].fetch_offers:  # catalog-only stores are done once their catalog is in
            week = schedule.week_start(now, schedule.weekday_of(row)).isoformat()
            fields.update(fetched_week=week, attempts_week=week, attempts=1, last_fetch_at=now_s,
                          last_success_at=now_s, last_error=None)
        if fields:
            db.update_store(row["id"], **fields)
        print(f"  {row['name']}: {count} products, {changed} price changes")
    db.log_fetch(None, "catalog", started, utc(dt.datetime.now(dt.timezone.utc)), "ok",
                 sum(len(v) for v in catalogs.values()), http.requests)
    return http.requests


def print_status(db, now):
    print(f"{'Store':12} {'Updates on':10} {'Source':10} {'Last fetched':20} {'Next fetch':17} Prices changed")
    for row in db.stores():
        nxt = schedule.next_fetch(schedule.weekday_of(row), row["fetched_week"], now).astimezone(dates.AMSTERDAM)
        source = "manual" if row["manual_update_weekday"] is not None else row["weekday_source"]
        print(f"{row['name']:12} {dates.WEEKDAYS[schedule.weekday_of(row)]:10} {source:10} "
              f"{(row['last_success_at'] or '-'):20} {nxt:%a %d %b %H:%M}  {row['catalog_changed_at'] or '-'}"
              + (f"  ERROR: {row['last_error']}" if row["last_error"] else ""))
    print(f"Requests in the last 7 days: {db.requests_since(utc(now - dt.timedelta(days=7)))}")


def _sync(action, what):
    """Runs a Supabase step; a Supabase problem is reported but never stops the update itself."""
    try:
        return action()
    except Exception as error:
        print(f"Supabase: could not {what} ({error})", file=sys.stderr)
        return None


def _output(name, value):
    """Passes a value to later GitHub Actions steps."""
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as handle:
            handle.write(f"{name}={value}\n")


if __name__ == "__main__":
    sys.exit(main())
