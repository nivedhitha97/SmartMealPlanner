"""Reads the Wikibooks Cookbook through the MediaWiki API (en.wikibooks.org/w/api.php).

The Cookbook's text is licensed CC BY-SA 4.0, so its recipes may be stored, adapted and shared with attribution
and under the same licence. Requests follow Wikimedia's API etiquette: one at a time, a User-Agent with contact
details, and `maxlag` so busy servers are left alone.
"""

import json
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://en.wikibooks.org/w/api.php"
USER_AGENT = "SmartMealPlanner/1.0 (https://github.com/nivedhitha97/SmartMealPlanner; recipe import)"
COOKBOOK_NAMESPACE = 102
BATCH = 50


class Wiki:
    def __init__(self, pause=0.5, opener=None):
        self.pause = pause
        self.opener = opener or urllib.request.urlopen
        self.requests = 0
        self._last = 0.0

    def get(self, **params):
        """One API call (format=json, formatversion=2), retried a few times when the servers are busy."""
        query = urllib.parse.urlencode({**params, "format": "json", "formatversion": 2, "maxlag": 5})
        request = urllib.request.Request(f"{API}?{query}", headers={"User-Agent": USER_AGENT})
        for attempt in range(5):
            wait = self.pause - (time.monotonic() - self._last)
            if wait > 0:
                time.sleep(wait)
            self._last = time.monotonic()
            self.requests += 1
            try:
                with self.opener(request, timeout=60) as response:
                    data = json.loads(response.read())
            except (urllib.error.URLError, TimeoutError, ConnectionError):
                if attempt == 4:
                    raise
                time.sleep(5 * (attempt + 1))
                continue
            if data.get("error", {}).get("code") == "maxlag":
                time.sleep(5 * (attempt + 1))
                continue
            if "error" in data:
                raise RuntimeError(f"Wikibooks API: {data['error']}")
            return data
        raise RuntimeError("Wikibooks API: still busy after 5 tries")

    def recipe_titles(self, category="Category:Recipes"):
        """Titles of the Cookbook pages in the category (the Cookbook's recipes)."""
        titles, cont = [], {}
        while True:
            data = self.get(action="query", list="categorymembers", cmtitle=category,
                            cmnamespace=COOKBOOK_NAMESPACE, cmlimit=500, cmtype="page", **cont)
            titles += [m["title"] for m in data["query"]["categorymembers"]]
            if "continue" not in data:
                return titles
            cont = {"cmcontinue": data["continue"]["cmcontinue"]}

    def pages(self, titles):
        """Each page's wikitext, revision id, categories and main image: {title: page}."""
        result = {}
        for start in range(0, len(titles), BATCH):
            batch = titles[start:start + BATCH]
            cont = {}
            while True:
                data = self.get(action="query", prop="revisions|categories|pageimages", rvprop="content|ids",
                                rvslots="main", cllimit="max", clshow="!hidden", piprop="name",
                                titles="|".join(batch), **cont)
                for page in data["query"]["pages"]:
                    if page.get("missing"):
                        continue
                    entry = result.setdefault(page["title"], {"title": page["title"], "pageid": page["pageid"],
                                                              "categories": []})
                    if page.get("revisions"):
                        revision = page["revisions"][0]
                        entry["revid"] = revision["revid"]
                        entry["text"] = revision["slots"]["main"]["content"]
                    entry["categories"] += [c["title"].removeprefix("Category:") for c in page.get("categories", [])]
                    if page.get("pageimage"):
                        entry["image"] = page["pageimage"]
                if "continue" not in data:
                    break
                cont = {k: v for k, v in data["continue"].items()}
        return result

    def image_info(self, names, width=640):
        """For image file names: a thumbnail URL and the licence metadata Wikimedia Commons keeps for the file."""
        result = {}
        names = list(dict.fromkeys(names))
        for start in range(0, len(names), BATCH):
            batch = names[start:start + BATCH]
            data = self.get(action="query", prop="imageinfo", iiprop="url|extmetadata", iiurlwidth=width,
                            titles="|".join(f"File:{name}" for name in batch))
            normalized = {n["to"]: n["from"] for n in data["query"].get("normalized", [])}
            for page in data["query"]["pages"]:
                info = (page.get("imageinfo") or [None])[0]
                if not info:
                    continue
                name = normalized.get(page["title"], page["title"]).removeprefix("File:")
                meta = info.get("extmetadata") or {}
                result[name] = {
                    "thumbURL": info.get("thumburl") or info.get("url"),
                    "pageURL": info.get("descriptionurl"),
                    "license": (meta.get("LicenseShortName") or {}).get("value"),
                    "licenseURL": (meta.get("LicenseUrl") or {}).get("value"),
                    "artist": (meta.get("Artist") or {}).get("value"),
                    "attributionRequired": (meta.get("AttributionRequired") or {}).get("value"),
                    "credit": (meta.get("Credit") or {}).get("value"),
                }
        return result
