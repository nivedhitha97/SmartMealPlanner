#!/usr/bin/env python3
"""
Sends the results of every test run to the SmartMealPlanner test report Google Sheet.

1. Finds every test case in SmartMealPlannerTests/ and SmartMealPlannerUITests/ (so tests that
   haven't run yet still get a row in the sheet).
2. Reads the results of a test run from an Xcode result bundle (.xcresult).
3. Posts them to the sheet's Apps Script web app (docs/test-report/Code.gs), which updates the
   "Test Cases" and "Run History" tabs.

Runs automatically after every test run in Xcode / xcodebuild (scheme post-test action) and in CI.
If the sheet can't be reached, the run is saved in TestReports/pending/ and sent with the next run.
Uses only the Python standard library.

Connection settings come from the TEST_REPORT_URL and TEST_REPORT_TOKEN environment variables, or
from TestReports/google-sheets.json (git-ignored), written by:
  scripts/update_test_report.py --configure WEB_APP_URL TOKEN

Usage:
  scripts/update_test_report.py                          # newest result bundle in DerivedData
  scripts/update_test_report.py --result path/to/Run.xcresult
  scripts/update_test_report.py --derived-data DIR       # newest bundle under DIR/Logs/Test
  scripts/update_test_report.py --sync-tests             # add new test cases without recording a run
  scripts/update_test_report.py --check                  # test the connection to the sheet
"""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
REPORT_DIR = REPO_ROOT / "TestReports"          # git-ignored: settings, state and unsent runs
CONFIG = REPORT_DIR / "google-sheets.json"
STATE = REPORT_DIR / "recorded-runs.json"
PENDING = REPORT_DIR / "pending"
TEST_DIRS = {"Unit": REPO_ROOT / "SmartMealPlannerTests", "UI": REPO_ROOT / "SmartMealPlannerUITests"}

# --------------------------------------------------------------------------------------------
# Discovering test cases in the source
# --------------------------------------------------------------------------------------------

def split_top_level(text: str, sep: str = ",") -> list[str]:
    """Split on `sep` outside brackets, so `[String: Int]` stays in one piece."""
    parts, depth, current = [], 0, []
    for ch in text:
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


def signature(name: str, params: str) -> str:
    """`f(raw: String, expected: [String])` → `f(raw:expected:)`, matching Xcode's test identifiers."""
    labels = []
    for param in split_top_level(params):
        head = param.split(":", 1)[0].strip()
        if not head:
            continue
        labels.append(head.split()[0] + ":")
    return f"{name}({''.join(labels)})"


def balanced_parens(text: str, start: int) -> tuple[str, int]:
    """Contents of the parenthesised group opening at text[start] == '(' and the index after it."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1:i], i + 1
    return text[start + 1:], len(text)


def describe(name: str) -> str:
    """`darkIconHasATransparentBackground` → `Dark icon has a transparent background`."""
    base = re.sub(r"^test(?=[A-Z])", "", name)
    words = re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[a-z])(?=[0-9])", " ", base).split()
    words = [w if (w.isupper() and len(w) > 1) else w.lower() for w in words]
    sentence = " ".join(words)
    return sentence[:1].upper() + sentence[1:]


def discover_tests() -> list[dict]:
    tests = []
    for kind, folder in TEST_DIRS.items():
        for path in sorted(folder.glob("*.swift")):
            source = path.read_text(encoding="utf-8")
            types = [(m.start(), m.group(2), None) for m in re.finditer(r"\b(struct|class)\s+(\w+)", source)]
            suites = {m.end(): m.group(1) for m in re.finditer(r'@Suite\("([^"]+)"\)', source)}

            def enclosing(position: int) -> tuple[str, str]:
                type_name, display = None, None
                for start, name, _ in types:
                    if start < position:
                        type_name = name
                        # @Suite("…") directly above this type
                        preceding = [(end, title) for end, title in suites.items() if end <= start]
                        display = preceding[-1][1] if preceding and start - preceding[-1][0] < 40 else None
                return type_name or path.stem, display

            if kind == "Unit":
                for match in re.finditer(r"@Test\b", source):
                    func = re.compile(r"\bfunc\s+(\w+)\s*\(").search(source, match.end())
                    if not func:
                        continue
                    params, _ = balanced_parens(source, func.end() - 1)
                    type_name, display = enclosing(func.start())
                    tests.append(new_case(kind, type_name, display, func.group(1), params, path, source, func.start()))
            else:
                for func in re.finditer(r"\bfunc\s+(test\w*)\s*\(", source):
                    params, _ = balanced_parens(source, func.end() - 1)
                    type_name, _ = enclosing(func.start())
                    tests.append(new_case(kind, type_name, None, func.group(1), params, path, source, func.start()))
    return tests


def new_case(kind, type_name, display, name, params, path, source, position) -> dict:
    suite = display or re.sub(r"(UI)?Tests$", "", type_name)
    return {
        "identifier": f"{type_name}/{signature(name, params)}",
        "type": kind,
        "suite": suite,
        "name": signature(name, params),
        "description": describe(name),
        "file": f"{path.parent.name}/{path.name}:{source.count(chr(10), 0, position) + 1}",
    }


# --------------------------------------------------------------------------------------------
# Reading a result bundle
# --------------------------------------------------------------------------------------------

def xcresult_json(bundle: Path, kind: str) -> dict:
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", str(bundle)],
                         check=True, capture_output=True, text=True)
    return json.loads(out.stdout)


def newest_bundle(search_roots: list[Path]) -> Path | None:
    bundles = []
    for root in search_roots:
        bundles += glob.glob(str(root / "Logs" / "Test" / "*.xcresult"))
        bundles += glob.glob(str(root / "*" / "Logs" / "Test" / "*.xcresult"))
    bundles = [Path(b) for b in bundles]
    return max(bundles, key=lambda b: b.stat().st_mtime) if bundles else None


def wait_for_bundle(bundle: Path, timeout: float) -> dict:
    """Xcode may still be finishing the bundle when the post-test action starts; retry briefly."""
    deadline = time.time() + timeout
    while True:
        try:
            return xcresult_json(bundle, "summary")
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            if time.time() > deadline:
                raise
            time.sleep(2)


def run_key(summary: dict) -> str:
    return f"{summary.get('startTime')}-{summary.get('finishTime')}"


def wait_for_new_bundle(roots: list[Path], recorded: set[str], timeout: float):
    """Poll until the newest result bundle is complete, not yet recorded, and from the run that just
    finished. Xcode writes the bundle as the tests finish, about a second before the post-test action
    starts, so a bundle that finished more than two minutes ago is a stale one from an earlier run."""
    not_before = time.time() - 120
    deadline = time.time() + timeout
    while time.time() < deadline:
        bundle = newest_bundle(roots)
        if bundle is not None:
            try:
                summary = xcresult_json(bundle, "summary")
                finished = summary.get("finishTime") or 0
                if finished >= not_before and run_key(summary) not in recorded:
                    return bundle, summary
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass  # still being written
        time.sleep(3)
    return None, None


def read_results(bundle: Path) -> list[dict]:
    tree = xcresult_json(bundle, "tests")
    results = []

    def failures(node) -> list[str]:
        found = [node["name"]] if node.get("nodeType") == "Failure Message" else []
        for child in node.get("children", []):
            found += failures(child)
        return found

    def walk(node, kind):
        node_type = node.get("nodeType")
        if node_type == "Unit test bundle":
            kind = "Unit"
        elif node_type == "UI test bundle":
            kind = "UI"
        if node_type == "Test Case" and node.get("nodeIdentifier"):
            argument_runs = [c for c in node.get("children", []) if c.get("nodeType") == "Arguments"]
            duration = node.get("durationInSeconds")
            if duration is None and argument_runs:
                durations = [c.get("durationInSeconds") for c in argument_runs if c.get("durationInSeconds") is not None]
                duration = sum(durations) if durations else None
            status = {"Expected Failure": "Passed"}.get(node.get("result"), node.get("result", "Unknown"))
            results.append({
                "identifier": node["nodeIdentifier"],
                "name": node.get("name"),
                "type": kind,
                "status": status,
                "duration": duration,
                "cases": max(len(argument_runs), 1),
                "failure": " | ".join(failures(node)),
            })
            return
        for child in node.get("children", []):
            walk(child, kind)

    for top in tree.get("testNodes", []):
        walk(top, None)
    return results



# --------------------------------------------------------------------------------------------
# Building the payload
# --------------------------------------------------------------------------------------------

def git(*args) -> str:
    try:
        return subprocess.run(["git", "-C", str(REPO_ROOT), *args], check=True, capture_output=True,
                              text=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def run_payload(bundle: Path, summary: dict, results: list[dict], tests: list[dict], source: str) -> dict:
    device = (summary.get("devicesAndConfigurations") or [{}])[0].get("device", {})
    descriptions = {t["identifier"]: t["description"] for t in tests}
    for result in results:
        result["description"] = descriptions.get(result["identifier"]) or describe(result["name"].split("(")[0])
    started, finished = summary.get("startTime"), summary.get("finishTime") or time.time()
    return {
        "run": {
            "key": run_key(summary),
            "started": started,
            "finished": finished,
            "source": source,
            "branch": os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME")
                      or git("rev-parse", "--abbrev-ref", "HEAD"),
            "commit": (os.environ.get("GITHUB_SHA") or git("rev-parse", "HEAD"))[:7],
            "device": f"{device.get('deviceName', '')} (iOS {device.get('osVersion', '?')})".strip(),
            "total": len(results),
            "passed": sum(r["status"] == "Passed" for r in results),
            "failed": sum(r["status"] == "Failed" for r in results),
            "skipped": sum(r["status"] == "Skipped" for r in results),
            "duration": round(finished - started, 1) if started else None,
            "result": summary.get("result", "Unknown"),
        },
        "tests": tests,
        "results": results,
    }


# --------------------------------------------------------------------------------------------
# Talking to the sheet
# --------------------------------------------------------------------------------------------

def load_config() -> dict | None:
    url, token = os.environ.get("TEST_REPORT_URL"), os.environ.get("TEST_REPORT_TOKEN")
    if url and token:
        return {"url": url, "token": token}
    if CONFIG.exists():
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    return None


def post(config: dict, payload: dict) -> dict:
    """POST to the Apps Script web app. Google answers with a redirect that urllib follows as a GET,
    which is how Apps Script returns the script's response."""
    body = json.dumps({**payload, "token": config["token"]}).encode("utf-8")
    request = urllib.request.Request(config["url"], data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=90) as response:
        text = response.read().decode("utf-8")
    try:
        reply = json.loads(text)
    except json.JSONDecodeError:
        raise RuntimeError("The web app didn't return JSON. Check that it's deployed with access for "
                           f"'Anyone' and that the URL ends in /exec. Got: {text[:200]}")
    if not reply.get("ok"):
        raise RuntimeError(f"The sheet rejected the update: {reply.get('error')}")
    return reply


def recorded_keys() -> set[str]:
    return set(json.loads(STATE.read_text())) if STATE.exists() else set()


def remember(key: str) -> None:
    keys = list(recorded_keys() | {key})
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(sorted(keys)[-200:]))


def send_or_queue(config: dict | None, payload: dict) -> str:
    """Send a run, after any runs still waiting from earlier. Unsent runs stay in TestReports/pending/."""
    PENDING.mkdir(parents=True, exist_ok=True)
    key = payload["run"]["key"] if payload.get("run") else f"sync-{time.time()}"
    if payload.get("run"):
        (PENDING / f"{re.sub(r'[^0-9A-Za-z.-]', '_', key)}.json").write_text(json.dumps(payload))
    if config is None:
        return ("Not sent: no sheet configured (set TEST_REPORT_URL / TEST_REPORT_TOKEN, or run "
                "scripts/update_test_report.py --configure URL TOKEN). Saved in TestReports/pending/.")
    messages = []
    for path in sorted(PENDING.glob("*.json"), key=lambda p: p.stat().st_mtime):
        queued = json.loads(path.read_text())
        reply = post(config, queued)
        path.unlink()
        remember(queued["run"]["key"])
        run = queued["run"]
        messages.append(f"{'already recorded' if reply.get('duplicate') else 'recorded'} run from "
                        f"{dt.datetime.fromtimestamp(run['finished']):%Y-%m-%d %H:%M} "
                        f"({run['passed']} passed, {run['failed']} failed, {run['skipped']} skipped)")
    if not payload.get("run"):
        reply = post(config, payload)
        messages.append(f"synced {reply.get('tests')} test cases")
    return "; ".join(messages) or "nothing to send"


# --------------------------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--result", type=Path, help="Path to a .xcresult bundle")
    parser.add_argument("--derived-data", type=Path, action="append", default=[],
                        help="Search for the newest .xcresult under this DerivedData folder (repeatable)")
    parser.add_argument("--source", default="local", help="Where the run happened: xcode, local, ci")
    parser.add_argument("--wait", type=float, default=60, help="Seconds to wait for a result bundle Xcode is still writing")
    parser.add_argument("--wait-for-new", action="store_true",
                        help="Wait (up to --wait seconds) for a result bundle that hasn't been recorded yet. "
                             "Used by the Xcode post-test action, which can start before Xcode has written the bundle.")
    parser.add_argument("--sync-tests", action="store_true", help="Add new test cases to the sheet without recording a run")
    parser.add_argument("--check", action="store_true", help="Test the connection to the sheet")
    parser.add_argument("--configure", nargs=2, metavar=("URL", "TOKEN"),
                        help="Save the web app URL and token to TestReports/google-sheets.json")
    args = parser.parse_args()

    if args.configure:
        REPORT_DIR.mkdir(exist_ok=True)
        CONFIG.write_text(json.dumps({"url": args.configure[0], "token": args.configure[1]}, indent=2) + "\n")
        print(f"Saved {CONFIG.relative_to(REPO_ROOT)}")
        return 0

    config = load_config()
    if args.check:
        if config is None:
            print("No sheet configured.", file=sys.stderr)
            return 1
        print(f"Connected to “{post(config, {'ping': True})['spreadsheet']}”.")
        return 0

    tests = discover_tests()
    if args.sync_tests:
        print(send_or_queue(config, {"tests": tests}))
        return 0

    roots = args.derived_data or [Path.home() / "Library/Developer/Xcode/DerivedData"]
    if args.result is None and args.wait_for_new:
        bundle, summary = wait_for_new_bundle(roots, recorded_keys(), args.wait)
        if bundle is None:
            print(f"No new result bundle appeared within {args.wait:.0f}s.", file=sys.stderr)
            return 1
    else:
        bundle = args.result or newest_bundle(roots)
        if bundle is None or not bundle.exists():
            print("No .xcresult bundle found; pass --result or --derived-data.", file=sys.stderr)
            return 1
        summary = wait_for_bundle(bundle, args.wait)

    payload = run_payload(bundle, summary, read_results(bundle), tests, args.source)
    try:
        print(f"{bundle.name}: {send_or_queue(config, payload)}")
    except (urllib.error.URLError, RuntimeError, TimeoutError) as error:
        print(f"{bundle.name}: not sent ({error}). Saved in TestReports/pending/ and will be sent with the next run.",
              file=sys.stderr)
        return 1
    return 0 if config else 1


if __name__ == "__main__":
    sys.exit(main())
