# Test report

| Kind | Count | Where | Runs in CI |
|---|---|---|---|
| Unit tests (Swift Testing) | 184 | `SmartMealPlannerTests` | iOS build |
| UI tests (XCUITest) | 22 | `SmartMealPlannerUITests` | iOS build |
| Grocery database tests (Python unittest) | 57 | `scripts/grocery_db/tests` | Grocery database |
| API and security checks (Postman/Newman) | 29 | `docs/api` | API checks |

**Latest results: all passing.** Every Xcode and CI test run is recorded in the
[SmartMealPlanner Test Cases](https://docs.google.com/spreadsheets/d/1YKWuDnbF0zmI1NbZde3dtsLhVRfhXbsNPPZ-43Ga_AE/edit)
Google Sheet (see below).

## Unit tests

| Suite | Covers |
|---|---|
| Plan generation | 7-day structure, diet/allergy/dislike/cuisine filtering, meal types, **no dish twice a day or more than twice a week**, unfilled slots, grocery aggregation scaled to people, offer matching (regional, national, nearby only), live prices, nutrition |
| Planning view model | Missing setup errors, generating/caching/clearing a plan, live prices and AI recipes reaching the planner |
| Weekly plan screen | Budget card, day picker, empty-slot labels |
| Recipe detail screen | Calories per serving, servings scaling, prep/cook/total times, links, bundled recipes complete |
| Recipe discovery | AI recipe conversion, allergen re-check, caching per preferences, unavailable model, prompt contents |
| External links | YouTube app first, Safari fallback, short links |
| Offers screen | Store and category filters, ending soon, ordering, savings, store badges, next update, store statuses |
| Grocery list | Offers, own items, editing, ticking off, plan items, filters, totals, saving, **purchases and weekly spending** |
| Live grocery data | No request before the next update, meta-only checks, rebuilt feed, offline fallbacks |
| Nearby stores | Chain matching, 2 km radius, nearest per chain, de-duplication, nearby-only offers |
| Offer alerts | Weekday mapping, weekly triggers, turning off, default store choice, permission |
| Preferences form / storage | Saving on first tap before the lookup, people, postcode rules, older saved data |
| Meal routine, Settings, App icon | Routine storage; appearance and version; icon variants |

## UI tests

Each test launches the app with no saved data, no splash and the bundled sample offers (`-uiTestingResetState`,
`-uiTestingSkipSplash`, `-uiTestingBundledData`), so results don't depend on the network.

| Class | Covers |
|---|---|
| Navigation | Splash, every tab opens its screen |
| Weekly plan | Setup checklist, generating before setup, full flow with 2 people (recipe shows "2 people", times, YouTube falls back to Safari), picking another day |
| Offers & preferences | Category filter, postcode errors and region, **first save keeps the postcode**, edits survive Meal routine |
| Grocery list | Store filter, adding offers and totals, own items (add/edit/tick/delete), plan groceries on the List tab, ticked items in the Profile |
| Settings | Version, theme choice and persistence, dark theme everywhere, **offer alerts per store** |

## Grocery database tests

Schedule (who is due when, retries, learning offer days), every store parser on samples of its real page data,
deal and per-item price maths, images, price history, the Supabase mirror (push only changes, never overwrite
edits, edits applied, first fill), and an end-to-end run with the network faked: a second run on the same day makes
no requests.

## API and security checks

The [Postman collection](api/SmartMealPlanner.postman_collection.json) checks every feed file against its schema and
data sanity, plus HTTPS and HSTS, security headers, no leaked secrets, no writes, 404 for unknown files, and the
Supabase mirror refusing requests without a key. Details: [API document](api/README.md#functional-and-security-checks-postman).

## Running the tests

```bash
xcodebuild test -project SmartMealPlanner.xcodeproj -scheme SmartMealPlanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Add `-only-testing:SmartMealPlannerTests` or `-only-testing:SmartMealPlannerUITests` for one kind; ⌘U in Xcode.
Python: `cd scripts && python3 -m unittest discover -s grocery_db/tests -t .`.
API: `npx newman run docs/api/SmartMealPlanner.postman_collection.json -e docs/api/feed.postman_environment.json`.

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
