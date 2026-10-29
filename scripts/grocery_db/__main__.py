"""Command line: python3 -m grocery_db update --data DIR   |   python3 -m grocery_db status --data DIR

Run from the scripts/ folder. `update` fetches every chain's offers and shelf prices from Open Prices (open data;
no supermarket website is read) once a day, saves them to DIR/grocery.db and writes the app's files next to it.

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
from .stores import BY_ID, STORES, openprices


def main(argv=None):
    parser = argparse.ArgumentParser(prog="grocery_db", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["update", "status", "sync"])
    parser.add_argument("--data", type=Path, default=Path("../build/grocery-data"), help="folder with grocery.db")
    parser.add_argument("--store", action="append", default=[], help="fetch this store again today")
    parser.add_argument("--all", action="store_true", help="fetch every store again today")
    parser.add_argument("--now", help="pretend it is this time (ISO 8601), for testing the schedule")
    parser.add_argument("--full", action="store_true", help="sync: send every row, not just changes")
    parser.add_argument("--no-sync", action="store_true", help="update: don't talk to Supabase")
    args = parser.parse_args(argv)

    now = dates.parse(args.now) if args.now else dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    args.data.mkdir(parents=True, exist_ok=True)
    db = Database(args.data / "grocery.db")
    db.sync_stores(STORES)
    removed = db.remove_data_not_from_open_prices()
    if removed:
        print(f"Removed {removed} rows that didn't come from Open Prices.")
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
        # Manual edits first, so they are in the files exported below.
        edits_changed = _sync(lambda: mirror.pull_overrides(db, supabase), "read manual edits") if supabase else False
        if edits_changed:
            print("Applied new manual edits from Supabase.")
        # A mirror that has never been filled is filled now, even on a day when no store is due.
        first_sync = bool(supabase) and db.sync_value("pushed_at") is None
        requests = update(db, now, forced)
        if requests is None and not edits_changed and not first_sync:
            print("Already fetched today; nothing to do.")
            _output("changed", "false")
            return 0
        if requests is None:
            print("Already fetched today." + (" Filling the Supabase mirror." if first_sync else ""))
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
    """Fetches every store's Open Prices data once a day (forced stores again). Returns the number of requests made,
    or None if everything was already fetched today."""
    today = now.astimezone(dates.AMSTERDAM).date().isoformat()
    now_s = utc(now)
    due = [row for row in db.stores() if row["id"] in forced or db.sync_value(f"open_prices:{row['id']}") != today]
    if not due:
        return None
    total = 0
    for row in due:
        store = BY_ID[row["id"]]
        http, started = web.Http(user_agent=openprices.USER_AGENT), utc(dt.datetime.now(dt.timezone.utc))
        try:
            offers, products = openprices.fetch(http, store.osm_name, today=now.astimezone(dates.AMSTERDAM).date())
            new = db.save_offers(store.id, offers, now_s)
            count, changed = db.save_catalog(store.id, products, now_s) if products else (0, 0)
            fields = {"fetched_week": today, "attempts_week": today, "attempts": 1, "last_fetch_at": now_s,
                      "last_success_at": now_s, "last_error": None}
            if products and (changed or not db.has_catalog(store.id) or row["catalog_changed_at"] is None):
                fields["catalog_changed_at"] = now_s
            db.update_store(store.id, **fields)
            db.set_sync_value(f"open_prices:{store.id}", today)
            db.log_fetch(store.id, "open-prices", started, utc(dt.datetime.now(dt.timezone.utc)), "ok",
                         len(offers) + count, http.requests)
            print(f"  {store.name}: {len(offers)} offers ({new} new), {count} shelf prices ({changed} changed), "
                  f"{http.requests} requests")
        except Exception as error:  # one store failing must not stop the others
            db.update_store(store.id, last_fetch_at=now_s, last_error=str(error)[:300])
            db.log_fetch(store.id, "open-prices", started, utc(dt.datetime.now(dt.timezone.utc)), "error",
                         requests=http.requests, message=str(error)[:300])
            print(f"  {store.name}: FAILED ({error})", file=sys.stderr)
            traceback.print_exc()
        total += http.requests
    return total


def print_status(db, now):
    print(f"{'Store':12} {'Offer week':10} {'Source':10} {'Last fetched':20} {'Next fetch':17} Prices changed")
    for row in db.stores():
        nxt = schedule.next_fetch(now).astimezone(dates.AMSTERDAM)
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
