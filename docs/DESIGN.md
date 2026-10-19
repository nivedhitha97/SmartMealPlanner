# Design

## Architecture

Service-oriented, MVVM-inspired SwiftUI. Screen rules live in plain Swift types (no SwiftUI) so they're unit tested;
views stay thin. Shared state is passed with `@EnvironmentObject` (`PlanningViewModel`, `ShoppingListStore`).

```
          ┌──────────────── iPhone app (SwiftUI) ─────────────────┐
          │ Views ──▶ ViewModels / screen logic ──▶ Services       │
          │  Plan       PlanningViewModel, MealPlanner             │
          │  Offers     OffersList                    GroceryDataService ──▶ grocery feed (HTTPS)
          │  List       ShoppingList(Store)           PostcodeLocationService, NearbyStores ──▶ Apple Maps
          │  Preferences PreferencesForm              RecipeDiscovery ──▶ on-device model
          │  Settings   AppSettings, WeekSpending     OfferAlertScheduler ──▶ local notifications
          └────────────────────────────────────────────────────────┘
                                                           ▲
 GitHub Actions (daily) ── scripts/grocery_db ──▶ grocery-feed branch (grocery.db.gz, offers/prices/meta.json)
        │  fetches stores due today (store websites + Checkjebon)        │
        └──▶ Supabase mirror (browse / edit) ◀── manual edits applied every morning
```

### Project structure

```
SmartMealPlanner/
├── SmartMealPlanner.swift         App entry (splash, tabs, notification delegate)
├── Models/                        Recipe, Ingredient, MealPlan, MealRoutine, UserPreferences, SupermarketOffer,
│                                  IngredientPrice, AISuggestedWeekPlan, DailyMealLog
├── Services/
│   ├── AIPlanningService.swift    Planner protocol + on-device heuristic planner (grocery pricing, notes)
│   ├── GroceryDataService.swift   Feed download, disk cache, offline/bundled fallback, store schedules
│   ├── PostcodeLocationService    Postcode → region, city, coordinates
│   ├── NearbyStoresService        Supermarkets within 2 km (Apple Maps)
│   ├── RecipeDiscovery            On-device AI recipes (Foundation Models), cached
│   ├── OfferAlerts                Weekly local notifications per store
│   └── ExternalLinks              YouTube app with Safari fallback
├── ViewModels/                    PlanningViewModel, MealPlanner (filtering, variety rules), WeeklyPlanContent,
│                                  OffersList, ShoppingList (+ purchases, weekly spending), PreferencesForm,
│                                  AppSettings
├── Views/                         MainTabView, SplashView, WeeklyPlanView, RecipeDetailView, WeeklyOffersView,
│                                  GroceryListView, PreferencesView, MealRoutineView, SettingsView
│   └── DesignSystem/              Theme (tokens, components), StoreBadge
└── Data/                          recipes.json, offers.json (offline samples), ingredients.json
scripts/grocery_db/                Grocery database (Python, stdlib): store fetchers, schedule, SQLite, export,
                                   Supabase mirror, tests
docs/                              Summary, features, design, test report, API (OpenAPI + Postman)
```

## Grocery database

A SQLite database of Dutch supermarket products, shelf prices with their history, and weekly offers, kept by
`scripts/grocery_db` in the **Grocery database** workflow and published gzipped to the `grocery-feed` branch with
the files the app reads ([API](api/README.md)).

**Each supermarket is fetched once a week, on the day its offer week starts**, learned from the stores' own offer
dates (re-learned after every fetch; overridable in Supabase):

| Store | Offer week | Offers from | Shelf prices |
|---|---|---|---|
| Albert Heijn | Mon–Sun | Open Prices (shopper-reported, checked daily) and deals you add from AH's Bonus page | Checkjebon (stale) |
| Lidl | Mon–Sun | lidl.nl offers API | Checkjebon (stale) |
| DekaMarkt | Tue–Mon | dekamarkt.nl offers page | Checkjebon (stale) |
| Jumbo, Dirk, Hoogvliet | Wed–Tue | their offers pages | Checkjebon (current for Jumbo) |
| Poiesz | Sun–Sat | Poiesz web shop offers page | Checkjebon |
| Spar, Plus, Vomar | – | – | Checkjebon (current for Spar) |

- The workflow runs every morning. On days when no store is due it only checks Open Prices for Albert Heijn
  (about 2 requests); a full week is about two dozen requests. A store that hasn't published its week yet is retried the next morning (up to three times).
- Offers keep real dates, deals (multi-buy priced per item; Jumbo's price-less deals priced from shelf prices) and a
  ~300 px product photo hosted by the store.
- Stores whose shelf prices stopped changing are flagged stale and left out of ingredient prices.
- Every fetch is logged with its request count (`fetch_log`); `meta.json` reports requests per 7 and 28 days.
- **The app downloads only when something can have changed:** nothing before `meta.nextUpdateAt`, then only the
  4 KB `meta.json`, and offers/prices only if the database was rebuilt.

Run locally (from `scripts/`): `python3 -m grocery_db update|status|sync --data ../build/grocery-data`
(`--all` to fetch every store now). Serve the folder and launch the app with
`-GroceryFeedBaseURL http://127.0.0.1:8000/` to try a local copy.

### Supabase mirror (browse and edit)

The database is mirrored to Supabase (free tier); its **Table Editor** shows every table as a searchable,
editable spreadsheet. Editable columns: `products.price_override`, `offers.offer_price_override` / `hidden`,
`stores.manual_update_weekday`; they're applied every morning and never overwritten. Row level security is on and
nothing is granted to the public key; the app never needs Supabase keys.

Setup: create a project, run [`supabase_schema.sql`](../scripts/grocery_db/supabase_schema.sql) in the SQL Editor
(again after schema changes: it only adds what's missing), and add `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` as
repository secrets. The first run sends everything; later runs only new and changed rows.

## Key decisions

| Decision | Why |
|---|---|
| Weekly per-store fetching instead of daily | Stores change offers once a week; fetching on that day cuts requests to about a dozen a week |
| Free, permission-light data sources | No paid APIs or keys in the app. Store websites and Checkjebon (MIT) for personal use; AH is not scraped because it blocks automated access |
| Albert Heijn through Open Prices and your own deals | Open Prices (Open Food Facts, ODbL) is free, open and legal but crowdsourced, so it has only a few AH discounts a week. It is checked once a day (about 2 requests), outside the weekly schedule. The app links to AH's own Bonus page and lets you add deals from it, stored only on the phone |
| Store badges instead of logo files | Brand-coloured monograms drawn by the app: no logo artwork to license, nothing to download or block |
| Apple Maps for location and nearby stores | Free, no key, accurate to street level for full Dutch postcodes |
| Local notifications instead of push | Offer days are known in advance, so the phone can schedule alerts itself: no server or push certificate |
| On-device AI for recipe discovery | Free and private; AI recipes are re-checked against allergies/diet and labelled |
| Plain-Swift screen logic | Rules (filters, totals, variety, scheduling) are unit tested without UI |

## Design system

UI designed in Figma ([Smart Meal Planner – UI Revamp](https://www.figma.com/design/mCMW5PlNeirvCva8Ns9EAs)) and
implemented in `Views/DesignSystem`:

- **Colour tokens** with light and dark variants: brand green (`brandPrimary`, `brandPrimaryDeep`, `brandPrimarySoft`),
  accents coral and amber, canvas/surface/muted backgrounds, text primary/secondary/tertiary, subtle borders
- **Typography:** large screen titles, section and card titles, system text styles for Dynamic Type
- **Components:** cards, chips, store chips (logo badges), badges, icon tiles and circles, primary/secondary
  buttons, section and screen headers, flow layout, food gradients for missing photos
- **Store badges:** each chain's monogram in its brand colours (AH blue, Jumbo yellow, Lidl blue/yellow, …)
- **Accessibility:** combined elements for cards, decorative icons hidden from VoiceOver, logo chips read the store
  name, 44 pt touch targets
