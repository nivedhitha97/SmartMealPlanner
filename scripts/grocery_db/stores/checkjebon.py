"""Checkjebon (github.com/supermarkt/checkjebon, MIT): shelf prices of the online assortments of Dutch
supermarkets in one daily file. One download serves every store due that day."""

import json
import urllib.parse

from ..records import Product

CURRENT_URL = "https://www.checkjebon.nl/data/supermarkets.json"
REPO = "supermarkt/checkjebon"
DATA_PATH = "data/supermarkets.json"


def fetch_catalogs(http):
    """{store id: [Product]} for every store in the file."""
    return parse(http.get(CURRENT_URL))


def fetch_catalogs_at(http, when, token=None):
    """The file as it was at `when` (a datetime), from the repository history; None if there is none."""
    query = urllib.parse.urlencode({"path": DATA_PATH, "until": when.strftime("%Y-%m-%dT%H:%M:%SZ"), "per_page": 1})
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    commits = http.json(f"https://api.github.com/repos/{REPO}/commits?{query}", headers=headers)
    if not commits:
        return None
    sha = commits[0]["sha"]
    return parse(http.get(f"https://raw.githubusercontent.com/{REPO}/{sha}/{DATA_PATH}"))


def parse(raw):
    catalogs = {}
    for store in json.loads(raw):
        base = store.get("u") or ""
        catalogs[store["n"]] = [
            Product(key=p["l"], name=p["n"], price=float(p["p"]), size=p.get("s") or "", url=base + p["l"])
            for p in store.get("d") or [] if p.get("p")
        ]
    return catalogs
