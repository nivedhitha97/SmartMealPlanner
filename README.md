# SmartMealPlanner – iOS (SwiftUI)

[![iOS build](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/swift.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/swift.yml)

## Project Overview

**Smart Meal Planner** is a SwiftUI-based iOS application designed to generate personalized meal plans based on user dietary preferences, meal routines, and nutritional goals. The project focuses on **clean architecture, scalability, and real-world problem solving**, and serves as a portfolio-quality demonstration of modern iOS development practices.

The app addresses a practical challenge faced by users—planning meals and groceries efficiently while managing nutrition, preferences, and budget—especially in environments with multiple supermarkets and food options.

---

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-launch.png" width="220" alt="Launch screen"/><br/><b>Launch screen</b></td>
    <td align="center"><img src="docs/screenshots/02-weekly-plan.png" width="220" alt="Weekly plan with budget card and planner notes"/><br/><b>Weekly plan</b><br/><sub>Budget tracking &amp; planner notes</sub></td>
    <td align="center"><img src="docs/screenshots/03-meals.png" width="220" alt="Day picker with meals and weekly nutrition"/><br/><b>Daily meals</b><br/><sub>Day picker &amp; weekly nutrition</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/04-recipe.png" width="220" alt="Recipe detail with photo, video and cookbook links"/><br/><b>Recipe detail</b><br/><sub>Photo, video &amp; cookbook links</sub></td>
    <td align="center"><img src="docs/screenshots/05-offers.png" width="220" alt="Regional supermarket offers"/><br/><b>Regional offers</b><br/><sub>Filter deals by category</sub></td>
    <td align="center"><img src="docs/screenshots/06-preferences.png" width="220" alt="Diet, breakfast and cuisine preferences"/><br/><b>Preferences</b><br/><sub>Diet, breakfast &amp; cuisines</sub></td>
  </tr>
</table>

UI designed in Figma: [Smart Meal Planner – UI Revamp](https://www.figma.com/design/mCMW5PlNeirvCva8Ns9EAs)

---

## Key Features

### User Preferences Management
- Supports dietary types (Vegetarian / Non-Vegetarian / Vegan / High Protein)
- Preferred cuisines and ingredient exclusions (allergies/dislikes)
- Breakfast mode: include breakfast recipes, or granola/muesli only
- Weekly grocery budget
- Shopping region derived from a Dutch postcode (city lookup via MapKit, region from the postcode)
- Preferences persisted globally using `UserDefaults`

### Meal Routine Configuration
- Customizable breakfast, lunch, and dinner routines
- Supports fixed, home-cooked, flexible, and outside meals

### Weekly Meal Planning Engine
- Generates a 7-day plan based on:
  - User preferences
  - Meal routine
  - Available recipes
- Intelligent filtering logic to exclude incompatible recipes (diet, allergies, dislikes, cuisines)
- Planner sits behind an `AIPlanningService` protocol, so the on-device heuristic can be swapped for a remote model

### Grocery List (List tab)
- One editable list: the weekly plan's groceries, offers added from the Offers screen, and your own items
- Filters: All, Added (offers and your own items) and each store; items are grouped by store with a subtotal, plus the overall total and what's left to buy
- Tap the circle to tick an item off, tap the row to edit its name, store, price or quantity (or delete it), and + to add your own; the List tab's badge shows how many items are left
- Saved on the device; a new plan replaces only the plan's items, everything you added stays
- The Plan screen shows a summary card that opens the list

### Budget-Aware Grocery List
- Aggregates ingredients across the week into one grocery list
- Prices each ingredient from a matching offer, else today's supermarket prices (typical price per 100 g across stores), else the recipe catalog
- Each line says where its price came from, e.g. the cheapest product and store
- Budget card shows progress against the weekly budget

### Live Supermarket Offers
- This week's offers from Jumbo, Lidl, Dirk, DekaMarkt, Hoogvliet and Poiesz, with their real end dates and deals, plus price drops at Spar
- Shows whether prices are live, saved from the last download (offline) or the bundled samples, when the next store refresh is, and each store's weekly update day; pull to refresh
- Product photos on the offer cards (store initials while loading or when there is none)
- Filtered by store and category, recipe ingredients first, with the deal or discount percentage and total savings
- A + button on each offer adds it to the grocery list; once added it shows the quantity, and tapping again adds one more

### Settings
- Light / dark theme choice (System, Light or Dark), remembered between launches
- App version and build number

### Nutrition Calculation
- Aggregates nutritional values per week and per recipe:
  - Calories
  - Protein
  - Carbohydrates
  - Fat

### Grocery Database
A SQLite database (`grocery.db`) of Dutch supermarket products, shelf prices with their full history, and weekly offers, kept up to date by `scripts/grocery_db` in GitHub Actions. The app downloads small files exported from it.

**Each supermarket is fetched once a week, on the day its offer week starts.** These days come from the stores' own offer dates and are re-learned after every fetch, so a store that moves its offer week is followed automatically:

| Store | Offer week | Offers from | Shelf prices |
|---|---|---|---|
| Albert Heijn | Mon – Sun | – (ah.nl blocks automated requests) | Checkjebon (stale) |
| Lidl | Mon – Sun | lidl.nl offers API | Checkjebon (stale) |
| DekaMarkt | Tue – Mon | dekamarkt.nl offers page | Checkjebon (stale) |
| Jumbo | Wed – Tue | jumbo.com promotions page | Checkjebon |
| Dirk | Wed – Tue | dirk.nl offers page | Checkjebon (stale) |
| Hoogvliet | Wed – Tue | hoogvliet.nl offers page | Checkjebon (stale) |
| Poiesz | Sun – Sat | Poiesz web shop offers page | Checkjebon |
| Spar, Plus, Vomar | – | – | Checkjebon (Spar current; Plus and Vomar stale) |

- The workflow (`.github/workflows/grocery-feed.yml`) runs every morning, but on days when no store is due it makes **no requests** and publishes nothing. A full week costs about a dozen requests: one per store's offers (three for Lidl) plus one shared [Checkjebon](https://github.com/supermarkt/checkjebon) catalog download on each update day
- If a store hasn't published its new week yet, it is tried again the next morning (up to three times)
- Offers keep the store's real start and end dates and deal ("1+1 gratis", "2 voor €5,00"); multi-buy prices are shown per item, and Jumbo's price-less deals are priced from the product's shelf price
- Offers include a product photo (`image_url`, about 300 px wide, hosted by the store; Dirk, DekaMarkt and Poiesz images are resized by their file servers). Nearly every offer has one; the catalog's shelf-price products don't, because Checkjebon has no images
- Checkjebon has stopped updating several stores (Albert Heijn, Plus, Hoogvliet and DekaMarkt prices haven't changed since at least December 2025). The database notices when a store's prices stop changing: stale shelf prices are left out of ingredient prices, and the Offers screen says so
- The database and the app's files (`offers.json`, `prices.json`, `meta.json`) live on the `grocery-feed` branch (the database gzipped). Nothing needs an API key: the job pushes with its own `GITHUB_TOKEN`
- Every fetch is logged with its request count (`fetch_log` table); `meta.json` reports requests in the last 7 and 28 days

**The app downloads only when something can have changed.** `meta.json` says when the next store refresh is due; until then the saved copy is used without any request. After that only the 4 KB `meta.json` is checked, and offers and prices are downloaded only if the database was rebuilt. The last good copy is also the offline fallback; with no download at all the app shows the bundled sample offers. Pull to refresh checks straight away. The Offers screen shows the next update and a "Store updates" list with each store's weekly day and whether its data is current.

Run it locally (from `scripts/`):

```
python3 -m grocery_db update --data ../build/grocery-data           # fetch the stores that are due
python3 -m grocery_db update --data ../build/grocery-data --all     # fetch every store now
python3 -m grocery_db status --data ../build/grocery-data           # schedule, last fetch, stale stores
python3 -m grocery_db sync --full --data ../build/grocery-data      # send everything to Supabase (needs the two env vars)
python3 -m unittest discover -s grocery_db/tests -t .               # tests
```

To try the app against a local copy, serve the folder (`python3 -m http.server 8000` in `build/grocery-data`) and launch the app with `-GroceryFeedBaseURL http://127.0.0.1:8000/`.

### Browse and Edit the Database (Supabase)
The database is mirrored to [Supabase](https://supabase.com) (hosted Postgres, free tier), whose **Table Editor** shows every table as a searchable, sortable, filterable spreadsheet at a URL, and lets you edit it.

- Tables: `stores` (weekly schedule), `products` (all shelf prices), `price_history`, `offers` (with `image_url`), `fetch_log`; views `offers_this_week` and `requests_per_week`. After a schema change, run `supabase_schema.sql` again: it only adds what's missing
- **Editable columns** (everything else is rewritten by the weekly update):
  - `products.price_override` (+ `override_note`): use this price instead of the store's
  - `offers.offer_price_override`, `offers.hidden`: correct an offer's price, or leave it out of the app
  - `stores.manual_update_weekday` (0 = Monday): fetch the store on this day instead
- Edits are applied the next morning (the daily run reads them even when no store is due) and are never overwritten by later fetches. Clearing an override undoes it
- Only you and the update job can see the data: row level security is on and nothing is granted to the public key. The app keeps downloading the exported files, so it never needs Supabase keys

**Setup (once):**
1. Create a free project at [supabase.com](https://supabase.com/dashboard) (region: Frankfurt or another EU region).
2. In **SQL Editor → New query**, paste [`scripts/grocery_db/supabase_schema.sql`](scripts/grocery_db/supabase_schema.sql) and run it.
3. In **Project Settings → API**, copy the **Project URL** and the **service_role** key (secret; never put it in the app or the repo).
4. Add them as repository secrets (GitHub → Settings → Secrets and variables → Actions): `SUPABASE_URL` and `SUPABASE_SERVICE_KEY`, or run `gh secret set SUPABASE_URL` and `gh secret set SUPABASE_SERVICE_KEY`, which prompt for the value.
5. Run the **Grocery database** workflow (Actions tab → Run workflow). The first run sends the whole database (~107,000 products); later runs send only new and changed rows.

Then open **Table Editor** in the Supabase dashboard. Free projects pause after a week without requests; the daily run keeps it active.

### Recipe Data Handling
- Recipes loaded from bundled JSON
- Recipe detail with photo, YouTube and cookbook links
- Data modeled using `Codable` for safe and maintainable parsing

---

## Technical Architecture

The application follows a **service-oriented, MVVM-inspired SwiftUI architecture**, emphasizing separation of concerns and testability.

```
SmartMealPlanner
│
├── SmartMealPlanner.swift          App entry point (splash + tab view)
│
├── Models                          Codable data types
│   ├── Recipe.swift, Ingredient.swift, MealPlan.swift
│   ├── MealRoutine.swift, UserPreferences.swift      (incl. UserDefaults load/save)
│   ├── SupermarketOffer.swift, IngredientPrice.swift, AISuggestedWeekPlan.swift
│   └── DailyMealLog.swift                            (nutrition totals)
│
├── Services
│   ├── AIPlanningService.swift     Planner protocol + on-device heuristic planner
│   ├── GroceryDataService.swift    Live offers and prices: download, disk cache, bundled fallback
│   ├── PostcodeLocationService.swift
│   └── JSONLoader.swift
│
├── ViewModels                      Screen logic, free of SwiftUI so it can be unit tested
│   ├── PlanningViewModel.swift     Generate / cache / clear the weekly plan
│   ├── MealPlanner.swift           Recipe filtering and meal selection
│   ├── WeeklyPlanContent.swift     Budget card, day picker, slots, grocery list
│   ├── OffersList.swift            Offer filtering (store, category), grouping, savings
│   ├── ShoppingList.swift          Editable grocery list: items, filters, store totals, saving
│   ├── PreferencesForm.swift       Preferences form ↔ saved preferences
│   └── AppSettings.swift           Theme choice, version string, UI-test launch flags
│
├── Views
│   ├── MainTabView.swift, SplashView.swift
│   ├── WeeklyPlanView.swift, RecipeDetailView.swift
│   ├── WeeklyOffersView.swift, GroceryListView.swift
│   ├── PreferencesView.swift, MealRoutineView.swift
│   ├── SettingsView.swift
│   └── DesignSystem/Theme.swift    Color tokens and shared components
│
└── Data
    └── recipes.json, offers.json (offline sample), ingredients.json

SmartMealPlannerTests               Unit tests (Swift Testing), one suite per screen
SmartMealPlannerUITests             UI tests (XCTest) that drive the running app
scripts/grocery_db/                 Grocery database: store fetchers, weekly schedule, SQLite, export
│   ├── stores/                     One fetcher per supermarket + Checkjebon catalog
│   ├── schedule.py, db.py, export.py, matching.py
│   ├── supabase.py, supabase_schema.sql   Mirror for browsing and manual edits
│   └── tests/                      Python unit tests (run in grocery-feed.yml)
scripts/update_test_report.py       Sends each test run to the test report Google Sheet
docs/test-report/Code.gs            Apps Script that records runs in the sheet
```

---

## Design & Engineering Highlights

- Implemented global state management using `ObservableObject` and `@EnvironmentObject`
- Encapsulated business logic (filtering, meal generation, nutrition calculation) in a dedicated service layer
- Applied `Codable` best practices, including optional handling and runtime UUID generation
- Ensured SwiftUI preview stability via dependency injection and mock environments
- Kept screen logic in plain Swift types (`PreferencesForm`, `WeeklyPlanContent`, `OffersList`) so views stay thin and the rules are unit tested
- Injected `UserDefaults`, the recipe catalog and the planner into `PlanningViewModel`, so tests run against isolated storage and a stub planner
- Designed the app with extensibility in mind (weekly plans, budgeting, API integration)

---

## Technology Stack

**Platform:** iOS  
**Language:** Swift  
**UI Framework:** SwiftUI  
**Architecture:** MVVM-inspired, Service Layer  
**State Management:** Combine (`ObservableObject`, `@Published`)  
**Data Persistence:** UserDefaults  
**Data Parsing:** Codable (JSON)  
**Location:** MapKit (`MKGeocodingRequest`)  
**Testing:** Swift Testing (unit), XCTest / XCUITest (UI)  
**CI:** GitHub Actions (Xcode 26, iOS Simulator)

---

## Getting Started

1. Clone the repository
2. Open `SmartMealPlanner.xcodeproj` in Xcode 26 or later (the app targets iOS 26)
3. Select the `SmartMealPlanner` scheme and build and run on the iOS Simulator
4. Begin exploration from `SmartMealPlanner.swift` and `MainTabView.swift`

No third-party dependencies are required.

---

## Testing

### Unit tests

Unit tests live in `SmartMealPlannerTests` and use Swift Testing. Each screen's rules are covered without driving the UI:

| Suite | Covers |
|---|---|
| Weekly plan screen | Budget card maths and copy, day picker opening on today, empty-slot labels |
| Planning view model | Missing preferences / routine errors, generating and caching a plan, restoring it on relaunch, clearing it, planner and catalog failures, live prices reaching the planner |
| Plan generation | 7-day structure, diet / allergy / dislike / cuisine filtering, meal-type rules, grocery aggregation, regional and national offer matching, live ingredient prices, nutrition totals |
| Live grocery data | No request before the next store refresh, only meta.json when the feed is unchanged, downloading a rebuilt feed (stubbed network), offline fallback to the cached feed and then the bundled offers, server errors, broken feeds, freshness line |
| Recipe detail screen | Calorie estimate, reference links, photo URL handling, meat and animal-product detection |
| Grocery list | Adding offers (and again for more), own items, editing and deleting, ticking off, plan groceries replaced by a new plan while added items stay, All / Added / store filters, store and overall totals, saving |
| Offers screen | Store and category filters, "Ending soon" grouping (live price drops excluded), ordering, total savings, discount badge, store initials, next-update line, store update statuses |
| Preferences form / storage | Loading and saving preferences, postcode validation and region rules, older saved data |
| Meal routine screen | Default routine, saving and loading, corrupt data |
| Settings screen | Appearance options and colour schemes, version string, launch flags |
| App icon | Light / dark / tinted icons present and 1024×1024; light icon has no alpha; dark and tinted have transparent backgrounds; dark artwork is bright enough; tinted icon is grayscale with the leaf cut out of the badge |

### Grocery database tests

`scripts/grocery_db/tests` (Python `unittest`, run by the grocery workflow before every update) covers the weekly schedule (which store is due when, retries, learning a store's offer day), each store parser on samples of its real page data, deal and per-item price maths, price history, and an end-to-end run with the network faked that checks a second run on the same day makes no requests.

### UI tests

UI tests live in `SmartMealPlannerUITests` and use XCUITest to drive the running app. Each test launches the app with `-uiTestingResetState` (start with no saved data), `-uiTestingSkipSplash` and `-uiTestingBundledData` (use the bundled sample offers, so results don't depend on the network or today's prices).

| Test class | Covers |
|---|---|
| Navigation | Splash screen on launch, every tab opens its screen |
| Weekly plan | Setup checklist, generating before setup, full flow: preferences → meal routine → generate → open a recipe, picking another day |
| Offers & preferences | Filtering offers by category, invalid postcode error, valid postcode shows its region |
| Grocery list | Store filter on Offers, adding offers (twice for two) and the totals on the List tab, store filter on the list, adding / editing / ticking off / deleting your own item, the Plan screen's card opening the list with the plan's groceries |
| Settings | Version number, System is the default, switching Dark / Light changes the rendered theme (checked from screenshot pixels), theme survives a relaunch, dark theme applies to other tabs |

Run everything in Xcode with **⌘U**, or from the command line:

```bash
xcodebuild test -project SmartMealPlanner.xcodeproj -scheme SmartMealPlanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Add `-only-testing:SmartMealPlannerTests` or `-only-testing:SmartMealPlannerUITests` to run one kind. The GitHub Actions workflow builds the app and runs both on every push and pull request to `develop`.

### Test case report (Google Sheets)

The [SmartMealPlanner Test Cases](https://docs.google.com/spreadsheets/d/1YKWuDnbF0zmI1NbZde3dtsLhVRfhXbsNPPZ-43Ga_AE/edit) sheet lists every unit and UI test case and is updated after each test run:

| Tab | Contents |
|---|---|
| Summary | Last run (when, where, device, result) and live totals: passed / failed / skipped / not run, overall and for unit vs UI tests, plus pass rate |
| Test Cases | One row per test: ID, type, suite, readable description, source file and line, number of argument cases, last status (colour-coded), last run time, duration, run / pass / fail counts, pass rate, the last 10 results and the last failure message |
| Run History | One row per test run, newest first: time, source (Xcode / CI / local), branch, commit, device, totals, duration and result |

How it stays up to date:

- **Xcode / `xcodebuild test`:** the shared scheme's post-test action runs `scripts/update_test_report.py` in the background after every test run (log: `TestReports/update.log`).
- **CI:** the workflow sends each run, including failed ones, using the `TEST_REPORT_URL` and `TEST_REPORT_TOKEN` repository secrets.
- **Manually:** `scripts/update_test_report.py --result path/to/Run.xcresult`, `--sync-tests` to add new test cases without recording a run, or `--check` to test the connection.

The script reads the result bundle and posts it to an Apps Script web app attached to the sheet ([`docs/test-report/Code.gs`](docs/test-report/Code.gs)), which updates the rows under a lock, so runs from your Mac and from CI end up in the same history and a run is never counted twice. Tests are discovered from the source, so new tests appear as **Not run** until they run, and a partial run (e.g. `-only-testing`) only updates the tests it ran. If the sheet can't be reached, the run is kept in `TestReports/pending/` and sent with the next one. The script only uses the Python standard library.

**One-time setup** (needed on each Mac that should report, and for CI):

1. In the sheet, open **Extensions → Apps Script** (or, if that won't open, create a new project at [script.google.com](https://script.google.com) while signed in to the account that owns the sheet), replace the editor's contents with `docs/test-report/Code.gs`, and save.
2. In the Apps Script editor, open **Project Settings → Script properties** and add `TOKEN` with a long random value.
3. **Deploy → New deployment → Web app**, with *Execute as: Me* and *Who has access: Anyone*. Authorise it and copy the web app URL (it ends in `/exec`).
4. On your Mac: `scripts/update_test_report.py --configure <web app URL> <token>`, then `scripts/update_test_report.py --check`. The settings are saved in `TestReports/google-sheets.json`, which git ignores.
5. For CI: add the same values as the repository secrets `TEST_REPORT_URL` and `TEST_REPORT_TOKEN` (Settings → Secrets and variables → Actions).

---

## Scalability & Future Enhancements

- Monthly meal planning
- Albert Heijn bonus offers and current shelf prices for the stores Checkjebon no longer updates (needs a source that isn't blocked)
- Supermarket price comparison per store in the grocery list
- Nutrition visualization using Swift Charts
- Backend/API integration (Firebase / Supabase)
- AI-assisted recipe recommendations

---

## Purpose of This Project

This project was built to:
- Demonstrate **production-ready SwiftUI development skills**
- Showcase architectural decision-making and clean code practices
- Solve a real-world problem with a scalable technical approach
- Serve as a professional portfolio project for iOS and mobile engineering roles

---

## Author

**Nivedhitha Parthasarathy**  
Senior Mobile Developer (iOS / React Native)

---

## Notes for Reviewers

This project emphasizes **architecture, maintainability, and real-world applicability** over UI polish alone. It is designed to be easily extendable and suitable as a foundation for larger-scale applications.

