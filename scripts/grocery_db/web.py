"""HTTP for the store fetchers: browser-like headers, retries, a pause between requests, and a request count
per store so every run records how many calls it made."""

import json
import time
import urllib.error
import urllib.request

USER_AGENT = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
              "(KHTML, like Gecko) Version/18.0 Safari/605.1.15")


class FetchError(Exception):
    pass


class Http:
    def __init__(self, pause=1.0, retries=2, timeout=60, opener=None, user_agent=USER_AGENT):
        self.user_agent = user_agent
        self.pause = pause
        self.retries = retries
        self.timeout = timeout
        self.opener = opener or urllib.request.urlopen
        self.requests = 0
        self._last = 0.0

    def get(self, url, headers=None, data=None):
        """Response body as bytes. `data` (a dict) is sent as a JSON POST."""
        body = json.dumps(data).encode() if data is not None else None
        request = urllib.request.Request(url, data=body, headers={
            "User-Agent": self.user_agent, "Accept-Language": "nl-NL,nl;q=0.9",
            **({"Content-Type": "application/json"} if body else {}), **(headers or {}),
        })
        for attempt in range(self.retries + 1):
            wait = self.pause - (time.monotonic() - self._last)
            if wait > 0:
                time.sleep(wait)
            self._last = time.monotonic()
            self.requests += 1
            try:
                with self.opener(request, timeout=self.timeout) as response:
                    return response.read()
            except urllib.error.HTTPError as error:
                if error.code < 500 or attempt == self.retries:  # 4xx won't get better by retrying
                    detail = error.read()[:300].decode("utf-8", errors="replace").strip()
                    where = url.split("?")[0]
                    raise FetchError(f"{where}: HTTP {error.code}" + (f" {detail}" if detail else "")) from error
            except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
                if attempt == self.retries:
                    raise FetchError(f"{url}: {error}") from error
            time.sleep(2 ** attempt * 2)
        raise FetchError(url)

    def text(self, url, **kwargs):
        return self.get(url, **kwargs).decode("utf-8", errors="replace")

    def json(self, url, **kwargs):
        return json.loads(self.get(url, **kwargs))
