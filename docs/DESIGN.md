# Design

## Architecture

Service-oriented, MVVM-inspired SwiftUI. Screen rules live in plain Swift types (no SwiftUI) so they're unit tested;
views stay thin. Shared state is passed with `@EnvironmentObject` (`PlanningViewModel`, `ShoppingListStore`).

```
          ┌──────────────── iPhone app (SwiftUI) ─────────────────┐
          │ Views ──▶ ViewModels / screen logic ──▶ Services       │
          │  Plan       PlanningViewModel, MealPlanner             │
          │  Offers     OffersList                    GroceryDataService ──▶ feed (HTTPS)
          │  List       ShoppingList(Store)           PostcodeLocationService, NearbyStores ──▶ Apple Maps
          │  Preferences PreferencesForm              RecipeDiscovery ──▶ RecipeLibrary ──▶ feed (recipes.json)
          │                                                └─ dish ideas (on-device model)
          │  Settings   AppSettings, WeekSpending     OfferAlertScheduler ──▶ local notifications
          └────────────────────────────────────────────────────────┘
                                                           ▲
 GitHub Actions (daily) ──▶ grocery-feed branch (offers/prices/meta.json, recipes.json, licences)
   ├─ scripts/grocery_db: Open Prices (shopper-reported, ODbL), every morning
   ├─ scripts/recipes: Wikibooks Cookbook (CC BY-SA 4.0) + USDA FoodData Central (public domain), every Monday
   └─▶ Supabase mirror (browse / edit) ◀── manual edits applied every morning
```

**Open data only.** No supermarket website is read and no paid or keyed API is used. Every source may be used and
shared under its licence, and the app credits each one (see [Data sources and licences](#data-sources-and-licences)).

### Project structure

```
SmartMealPlanner/
├── SmartMealPlanner.swift         App entry (splash, tabs, notification delegate, legacy data clean-up)
├── Models/                        Recipe (+ RecipeCredit), Ingredient, MealPlan, MealRoutine, UserPreferences,
│                                  SupermarketOffer, IngredientPrice, AISuggestedWeekPlan, DailyMealLog
├── Services/
│   ├── AIPlanningService.swift    Planner protocol + on-device heuristic planner (grocery pricing, notes)
│   ├── GroceryDataService.swift   Feed download, disk cache, offline fallback (no sample data), store schedules
│   ├── RecipeLibrary              The Wikibooks recipes from the feed: daily download, offline copy
│   ├── RecipeDiscovery            Recipes for the preferences, dish ideas from the on-device model first
│   ├── LegacyDataCleanup          Removes recipes earlier versions saved (Spoonacular, AI)
│   ├── PostcodeLocationService    Postcode → region, city, coordinates
│   ├── NearbyStoresService        Supermarkets within 2 km (Apple Maps)
│   ├── OfferAlerts                Weekly local notifications per store
│   └── ExternalLinks              YouTube app with Safari fallback
├── ViewModels/                    PlanningViewModel, MealPlanner (filtering, variety rules, budget), WeeklyPlanContent,
│                                  OffersList, ShoppingList (+ purchases, weekly spending), PreferencesForm,
│                                  AppSettings
├── Views/                         MainTabView, SplashView, WeeklyPlanView, RecipeDetailView, WeeklyOffersView,
│                                  GroceryListView, PreferencesView, MealRoutineView, SettingsView, LegalView
│   └── DesignSystem/              Theme (tokens, components), StoreBadge
├── Legal/                         PRIVACY.md, TERMS.md, CREDITS.md (shown in Settings, linked from the README)
└── Data/                          UITestRecipes.json, UITestOffers.json: fixed data for UI tests only
scripts/grocery_db/                Grocery database (Python, stdlib): Open Prices fetcher, SQLite, export, Supabase
                                   mirror, tests
scripts/recipes/                   Recipe importer (Python, stdlib): Wikibooks API, wikitext parser, amounts in
                                   grams, ingredient table (foods.json from USDA data), tests
supabase/cleanup.sql               One-time clean-up of data earlier versions stored in Supabase
docs/                              Summary, features, design, test report, API (OpenAPI + Postman)
LICENSE                            The app's own code: all rights reserved
```

## Grocery database

A SQLite database of shopper-reported prices and offers for Dutch supermarkets, kept by `scripts/grocery_db` in the
**Grocery database** workflow and published gzipped to the `grocery-feed` branch with the files the app reads
([API](api/README.md)).

**Source: [Open Prices](https://prices.openfoodfacts.org/)** (Open Food Facts), where shoppers photograph shelf tags
and receipts. It is open data under the ODbL, so it may be used and shared with the attribution "Price data © Open
Food Facts contributors, ODbL". The feed built from it is a derived database and is shared under the ODbL too
(`LICENSE.md` on the feed branch).

- **Every chain, once a day:** for each chain (Albert Heijn, Aldi, DekaMarkt, Dirk, Hoogvliet, Jumbo, Lidl, Plus,
  Poiesz, Spar, Vomar), its Dutch stores on Open Prices are looked up, then their prices from the last 90 days: about
  two requests per chain, with an honest user agent naming the project.
- **Offers** are discounted prices seen in the last week, valid for the Monday-to-Sunday week they were seen in.
  **Shelf prices** are the latest regular price of each product; they feed the ingredient prices (median of each
  store's cheapest match per 100 g).
- The data is crowdsourced, so there are only a few prices: the planner falls back on the project's own estimated
  ingredient prices (in the recipes), and the Offers screen invites you to add deals from the stores' own folders.
- No product photos are used (Open Food Facts photos have their own licence).
- Each store's offer-week day (a public fact) is kept for the offer alerts and the Store updates list.
- Every fetch is logged with its request count (`fetch_log`); `meta.json` reports requests per 7 and 28 days.
- Rows that didn't come from Open Prices (from earlier versions, which read supermarket websites and Checkjebon) are
  deleted on every run, so they can never be published again.
- **The app downloads only when something can have changed:** nothing before `meta.nextUpdateAt`, then only the
  small `meta.json`, and offers/prices only if the database was rebuilt.

Run locally (from `scripts/`): `python3 -m grocery_db update|status|sync --data ../build/grocery-data`
(`--all` to fetch every store again today). Serve the folder and launch the app with
`-GroceryFeedBaseURL http://127.0.0.1:8000/` to try a local copy.

### Supabase mirror (browse and edit)

The database is mirrored to Supabase (free tier); its **Table Editor** shows every table as a searchable,
editable spreadsheet. Editable columns: `products.price_override`, `offers.offer_price_override` / `hidden`,
`stores.manual_update_weekday`; they're applied every morning and never overwritten. Row level security is on and
nothing is granted to the public key; the app never needs Supabase keys.

Setup: create a project, run [`supabase_schema.sql`](../scripts/grocery_db/supabase_schema.sql) in the SQL Editor
(again after schema changes: it only adds what's missing), and add `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` as
repository secrets. The first run sends everything; later runs only new and changed rows. A project that hosted the
earlier recipe search or mirror data from supermarket websites is cleaned once with
[`supabase/cleanup.sql`](../supabase/cleanup.sql).

## Recipes

The app ships no recipes of its own, and AI never writes or rewrites one: every recipe is a human-written recipe from
the **[Wikibooks Cookbook](https://en.wikibooks.org/wiki/Cookbook)**, licensed CC BY-SA 4.0, which allows storing,
adapting and sharing it with attribution and under the same licence.

**Import (`scripts/recipes`, every Monday in the workflow):**

1. All pages in the Cookbook's recipe category are read through the MediaWiki API (about 125 requests, one at a time,
   with a User-Agent naming the project and `maxlag`, as Wikimedia's API etiquette asks).
2. Only meals are kept (mains, soups, stews, curries, dals, salads, side dishes, breakfasts; no desserts, drinks,
   sauces or baking). The page's wikitext gives the servings, total time, ingredient lines and numbered method.
3. Every ingredient line is read into a quantity, unit and ingredient, matched against an ingredient table
   (`foods_spec.py` → `foods.json`): nutrition per 100 g and portion weights (a cup, a tablespoon, a medium piece, a
   clove) come from **USDA FoodData Central** (SR Legacy, public domain), prices are the project's own estimates. A
   recipe is kept only if every ingredient can be named and weighed, so its grocery list is complete.
4. Cuisines come from the Cookbook's categories (Indian, Asian, Italian, Mexican, Greek, French, Dutch, …), or from
   well-known dish names when a page has none; breakfasts are marked for breakfast, the rest for lunch and dinner.
5. A page's photo is used only when Wikimedia Commons lists a free licence (public domain, CC0, CC BY, CC BY-SA) and
   an author to credit.

**Credits (CC BY-SA 4.0).** Every recipe keeps the link to the exact page revision it came from (`oldid`), the page
history listing its authors, the licence, and a note of what was changed ("amounts converted to grams and ingredients
named from a standard list"). The method is the authors' own text, and the ingredient lines are kept as written next
to the gram amounts. The recipe page in the app shows all of this in **About this recipe**, with the photo's author and
licence; the feed's `RECIPES-LICENSE.md` licences the adapted recipes under CC BY-SA 4.0.

**In the app.** `RecipeLibrary` downloads `recipes.json` at most once a day and keeps it for offline use; with no copy
and no connection the plan screen says recipes need an internet connection (never sample recipes). `RecipeDiscovery`
filters them on the phone by diet, allergies and dislikes (so preferences never leave the phone), keeps lunches and
dinners to the chosen cuisines and lets breakfasts come from any cuisine. Where Apple Intelligence is on, Apple's
on-device model suggests dish names that fit the preferences and recipes with those names come first; the model never
writes a recipe. "Watch" opens a YouTube search for the dish (a plain link; no YouTube API).

At launch, `LegacyDataCleanup` deletes recipes earlier versions saved (from Spoonacular, whose terms require deleting
its data once it is no longer used, or written by AI) and a saved plan made from them.

## Data sources and licences

| Data | Source | Licence | Where it's credited |
|---|---|---|---|
| Recipes | Wikibooks Cookbook contributors | CC BY-SA 4.0 | Every recipe page (revision, authors, licence, changes); feed `RECIPES-LICENSE.md`; Settings → Data sources |
| Recipe photos | Wikimedia Commons | Each photo's own (PD, CC0, CC BY, CC BY-SA) | Every recipe page (author, licence, source) |
| Nutrition, portion weights | USDA FoodData Central (SR Legacy) | Public domain (CC0 1.0) | Settings → Data sources; feed |
| Offers, shelf prices | Open Prices, Open Food Facts contributors | ODbL (feed shared under ODbL) | Offers screen; feed `LICENSE.md`, `meta.json`; Settings |
| Ingredient price estimates | The project | – | Terms of use |
| Postcode lookup, nearby stores | Apple Maps (MapKit) | Apple's terms | Privacy policy |

Supermarket names are trademarks of their owners and are used only to say where an offer is from; the app shows no
logos and no brand colours, and says it is not affiliated with any supermarket. The privacy policy, terms of use and
data sources are in `SmartMealPlanner/Legal/` and in Settings → Privacy and legal. The app's own code is all rights
reserved (`LICENSE`).

## Key decisions

| Decision | Why |
|---|---|
| Open data only | Every source may be used and shared under its licence without asking anyone: Wikibooks (CC BY-SA), USDA (public domain), Open Prices (ODbL). No supermarket website is read, no keys or paid APIs |
| Wikibooks recipes, imported weekly | Human-written recipes that may be stored for offline use, unlike API data that may only be cached briefly; checking every ingredient makes complete grocery lists |
| Open Prices for offers and prices, daily | Legal and free, though crowdsourced and sparse; the project's estimates fill the gaps and you can add deals from the stores' folders |
| No logos or brand colours | Store names say where an offer is from; logos and brand colours could suggest an affiliation |
| Everything on the phone | No accounts, analytics or tracking; allergies and diet are filtered on the phone and never sent |
| Apple Maps for location and nearby stores | Free, no key, accurate to street level for full Dutch postcodes |
| Local notifications instead of push | Offer days are known in advance, so the phone can schedule alerts itself: no server or push certificate |
| AI chooses, never writes | Recipes people wrote are trustworthy; the free on-device model only suggests which dishes to prefer |
| Plain-Swift screen logic | Rules (filters, totals, variety, scheduling) are unit tested without UI |

## Design system

UI designed in Figma ([Smart Meal Planner – UI Revamp](https://www.figma.com/design/mCMW5PlNeirvCva8Ns9EAs)) and
implemented in `Views/DesignSystem`:

- **Colour tokens** with light and dark variants: brand green (`brandPrimary`, `brandPrimaryDeep`, `brandPrimarySoft`),
  accents coral and amber, canvas/surface/muted backgrounds, text primary/secondary/tertiary, subtle borders
- **Typography:** large screen titles, section and card titles, system text styles for Dynamic Type
- **Components:** cards, chips, store chips (initials and name), badges, icon tiles and circles, primary/secondary
  buttons, section and screen headers, flow layout, food gradients for missing photos
- **Store badges:** the store's initials on a square tile in the app's own green, never a logo or brand colour
- **Accessibility:** combined elements for cards, decorative icons hidden from VoiceOver, store chips read the store
  name, 44 pt touch targets
