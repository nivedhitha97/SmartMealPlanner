# Test report

| Kind | Count | Where | Runs in CI |
|---|---|---|---|
| Unit tests (Swift Testing) | 220 | `SmartMealPlannerTests` | iOS build |
| UI tests (XCUITest) | 26 (+ 1 screenshot test, skipped unless asked for) | `SmartMealPlannerUITests` | iOS build |
| Grocery database tests (Python unittest) | 45 | `scripts/grocery_db/tests` | Grocery database |
| Recipe importer tests (Python unittest) | 12 | `scripts/recipes/tests` | Grocery database |
| API, licence and security checks (Postman/Newman) | 44 | `docs/api` | API checks |

**Latest results: all passing.** Every Xcode and CI test run is recorded in the
[SmartMealPlanner Test Cases](https://docs.google.com/spreadsheets/d/1YKWuDnbF0zmI1NbZde3dtsLhVRfhXbsNPPZ-43Ga_AE/edit)
Google Sheet (see below).

## Unit tests

| Suite | Covers |
|---|---|
| Plan generation | 7-day structure, **staying within budget** (cheaper swaps, usual meals kept, **never more than the budget plus 10%**: as few meals left open as possible, usual meals last, marked and explained), diet/allergy/dislike/cuisine filtering, meal types, **no dish twice a day or more than twice a week**, unfilled slots, grocery aggregation scaled to people, offer matching (regional, national, nearby only), live prices, nutrition |
| Planning view model | Missing setup errors, generating/caching/clearing a plan, live prices and the recipes reaching the planner, the Wikibooks credit in the notes |
| Weekly plan screen | Budget card, day picker, empty-slot labels (including meals left open for the budget) |
| Recipe detail screen | Calories per serving, servings scaling, prep/cook/total times (total only when that's all the recipe gives), links |
| Recipe discovery | **Wikibooks recipes become credited app recipes** (source revision, authors, CC BY-SA 4.0, the changes, photo only with its author, the lines as written, YouTube search link, a stable id); filtering by diet, allergies and dislikes on the phone, lunches and dinners in the chosen cuisines, breakfasts from any; **dish ideas first**, tidied and limited to 8, the prompt carries the preferences; offline the copy on the phone, else a clear note; **recipes from earlier versions (Spoonacular, AI) and plans made from them are deleted** |
| Deals you add | Validity, saving on the phone, ending on Sunday (Amsterdam time), dropping ended deals, the planner using a linked deal, Open Prices credit |
| External links | YouTube and Albert Heijn apps first, Safari fallback, short links |
| Offers screen | Store and category filters, ending soon, ordering, savings, store initials (**no supermarket logos in the app**), next daily update, store statuses |
| Grocery list | Offers, own items, editing, ticking off, plan items, filters, totals, saving, **purchases and weekly spending**, **sharing** |
| Live grocery data | No request before the next update, meta-only checks, rebuilt feed, offline: the saved copy, else **no data (never samples)** |
| Nearby stores | Chain matching, 2 km radius, nearest per chain, de-duplication, nearby-only offers |
| Offer alerts | Weekday mapping, weekly triggers, turning off, default store choice, permission |
| Preferences form / storage | Saving on first tap before the lookup, people, postcode rules, older saved data |
| Meal routine, Settings, App icon | Routine storage; appearance and version; icon variants |

## UI tests

Each test launches the app with no saved data, no splash and fixed test offers and recipes (`-uiTestingResetState`,
`-uiTestingSkipSplash`, `-uiTestingBundledData`, reading `UITestOffers.json` and `UITestRecipes.json`), so results
don't depend on the network. Users never see that data: without it the app only shows downloaded data.

| Class | Covers |
|---|---|
| Navigation | Splash, every tab opens its screen |
| Weekly plan | Setup checklist, generating before setup, full flow with 2 people (recipe shows "2 people", times, YouTube falls back to Safari), picking another day |
| Offers & preferences | Category filter, **adding an Albert Heijn Bonus deal**, postcode errors and region, **first save keeps the postcode** (lookup delayed so the save happens during it), edits survive Meal routine |
| Screenshots | Takes the README screenshots with live data; runs only with `TEST_RUNNER_SCREENSHOT_DIR` set (see below) |
| Grocery list | Store filter, adding offers and totals, own items (add/edit/tick/delete), sharing the list, plan groceries on the List tab, ticked items in the Profile |
| Settings | Version, theme choice and persistence, dark theme everywhere, **offer alerts per store**, **sharing the app**, **privacy policy, terms and data sources open and show their text** |

## Grocery database tests

The Open Prices fetcher on samples of its API data (discounts as offers for their week, shelf prices, only the chain's
Dutch stores, an honest user agent, no product photos, no supermarket website in the code), the daily update with the
network faked (every store once a day, forced stores again, nothing the second time), the export with its ODbL licence
and attribution, **removal of every row not from Open Prices**, price history, deal and per-item price maths, and the
Supabase mirror (push only changes, never overwrite edits, edits applied, first fill).

## Recipe importer tests

On small hand-written samples shaped like Cookbook pages: wiki markup to plain text, the recipe summary (servings,
total time), only the ingredient list and the numbered method, amounts (metric in brackets wins, fractions, ranges,
sizes, units, no amount), a page becoming a credited recipe (source revision, authors, CC BY-SA 4.0, the changes, the
authors' own steps, grams from USDA portion weights, the juice of a lemon, no water), stable ids, desserts and
recipes with an unknown ingredient left out, breakfasts and cuisines from dish names, peppers told apart, and photos
only with a free licence and an author.

## API and security checks

The [Postman collection](api/SmartMealPlanner.postman_collection.json) checks every feed file against its schema and
data sanity, the licences (ODbL credit, every offer from Open Prices without photos, every recipe crediting its
Wikibooks revision and authors, photos only with an author and a free licence, both licence files published), plus
HTTPS and HSTS, security headers, no leaked secrets, no writes, 404 for unknown files, and the Supabase mirror refusing
requests without a key. Details: [API document](api/README.md#functional-and-security-checks-postman).

## Running the tests

```bash
xcodebuild test -project SmartMealPlanner.xcodeproj -scheme SmartMealPlanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Add `-only-testing:SmartMealPlannerTests` or `-only-testing:SmartMealPlannerUITests` for one kind; ⌘U in Xcode.
Python: `cd scripts && python3 -m unittest discover -s grocery_db/tests -t . && python3 -m unittest discover -s recipes/tests -t .`.
API: `npx newman run docs/api/SmartMealPlanner.postman_collection.json -e docs/api/feed.postman_environment.json`.
README screenshots (live data, simulator in light mode):

```bash
TEST_RUNNER_SCREENSHOT_DIR="$PWD/docs/screenshots" xcodebuild test -project SmartMealPlanner.xcodeproj -scheme SmartMealPlanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SmartMealPlannerUITests/ScreenshotTests
sips -Z 1000 docs/screenshots/*.png   # README size (460 × 1000)
```

## Test case report (Google Sheets)

The sheet lists every unit and UI test and is updated after each run:

| Tab | Contents |
|---|---|
| Summary | Last run and live totals (passed / failed / skipped / not run, unit vs UI, pass rate) |
| Test Cases | One row per test: ID, type, suite, description, source, status, last run, duration, counts, pass rate, last 10 results, last failure |
| Run History | One row per run: time, source (Xcode / CI / local), branch, commit, device, totals, duration, result |

- **Xcode / `xcodebuild test`:** the shared scheme's post-test action runs `scripts/update_test_report.py` in the
  background (log: `TestReports/update.log`).
- **CI:** the iOS build workflow sends each run with the `TEST_REPORT_URL` and `TEST_REPORT_TOKEN` secrets.
- **Manually:** `scripts/update_test_report.py --result path/to/Run.xcresult`, `--sync-tests`, or `--check`.

The script posts to an Apps Script web app ([`docs/test-report/Code.gs`](test-report/Code.gs)) that updates the
sheet under a lock, so Mac and CI runs share one history and no run is counted twice. Unreachable runs wait in
`TestReports/pending/`.

**One-time setup:** paste `Code.gs` into the sheet's Apps Script (or a project at script.google.com), add a `TOKEN`
script property, deploy as a web app (Execute as: Me, Who has access: Anyone), then run
`scripts/update_test_report.py --configure <web app URL> <token>` and add the same values as the CI secrets.
