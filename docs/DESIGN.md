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
          │  Preferences PreferencesForm              RecipeDiscovery ──▶ recipe-search function, else on-device model
          │  Settings   AppSettings, WeekSpending     OfferAlertScheduler ──▶ local notifications
          └────────────────────────────────────────────────────────┘
                                                           ▲
 GitHub Actions (daily) ── scripts/grocery_db ──▶ grocery-feed branch (grocery.db.gz, offers/prices/meta.json)
        │  fetches stores due today (store websites + Checkjebon)        │
        └──▶ Supabase mirror (browse / edit) ◀── manual edits applied every morning

 Supabase Edge Function recipe-search ──▶ Spoonacular (recipes) ──▶ Claude Haiku (adapt to the app's format)
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
│   ├── RecipeDiscovery            AI recipes: recipe search first, on-device model (Foundation Models) as
│   │                              fallback; cached per preferences
│   ├── RecipeSearchService        Client for the recipe-search function (Spoonacular + Claude Haiku)
│   ├── OfferAlerts                Weekly local notifications per store
│   └── ExternalLinks              YouTube app with Safari fallback
├── ViewModels/                    PlanningViewModel, MealPlanner (filtering, variety rules), WeeklyPlanContent,
│                                  OffersList, ShoppingList (+ purchases, weekly spending), PreferencesForm,
│                                  AppSettings
├── Views/                         MainTabView, SplashView, WeeklyPlanView, RecipeDetailView, WeeklyOffersView,
│                                  GroceryListView, PreferencesView, MealRoutineView, SettingsView
│   └── DesignSystem/              Theme (tokens, components), StoreBadge
└── Data/                          recipes.json, offers.json (offline samples), ingredients.json,
                                   RecipeSearch.json (recipe-search address and app key; empty = off)
scripts/grocery_db/                Grocery database (Python, stdlib): store fetchers, schedule, SQLite, export,
                                   Supabase mirror, tests
supabase/functions/recipe-search/  Edge Function (Deno): Spoonacular search, Claude Haiku adaptation, cache,
                                   daily limits; logic tested with Node
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

## Recipe search

With **Discover new recipes** on, the planner adds recipes found for the user's preferences:

1. The app sends only the diet, cuisines, allergies, dislikes and number of people (no postcode or budget) to the
   `recipe-search` Supabase Edge Function.
2. The function asks **Spoonacular** for up to 20 real main-course recipes: the diet and cuisines as filters,
   allergies as Spoonacular intolerances (others as excluded ingredients), dislikes excluded.
3. **Claude Haiku** (`claude-haiku-5-5`) puts up to 10 of them in the app's format through a forced tool call: every
   ingredient in grams, nutrition per 100 g (from Spoonacular's data where given), Dutch supermarket prices, 6–10
   detailed steps (amounts, heat, timings). It is told to drop any recipe with an allergen or disliked ingredient and never to add ingredients.
4. The function checks the result: only recipes that really came from Spoonacular, numbers clamped to sensible
   ranges, the photo and source link taken from Spoonacular (never from the model), and banned ingredients filtered
   again. The app filters a third time with the same rules as the bundled recipes, credits Spoonacular with a link
   to the original, and labels the recipe "Adapted by AI from Spoonacular: check ingredients for allergens".

If the function isn't set up or fails, Apple's on-device model writes recipes instead (when Apple Intelligence is
available); otherwise only the bundled recipes are used.

**Keys and cost.** The Spoonacular and Anthropic keys exist only as Supabase secrets. Results are cached for 7 days
per set of preferences (cache hits cost nothing), and new searches are capped per caller (10 a day) and in total
(`RECIPE_SEARCH_DAILY_LIMIT`, default 40 a day). The limit fails closed if the log can't be read. The app key in the
app only keeps out casual callers, since anything shipped in an app can be extracted.

**Setting it up**

1. Get a [Spoonacular API key](https://spoonacular.com/food-api/console) (free plan) and an
   [Anthropic API key](https://console.anthropic.com/).
2. In the Supabase SQL editor, run [`supabase/recipe_search_schema.sql`](../supabase/recipe_search_schema.sql).
3. With the [Supabase CLI](https://supabase.com/docs/guides/cli), from the repository root:
   ```bash
   supabase link --project-ref <your-project-ref>
   supabase secrets set SPOONACULAR_API_KEY=… ANTHROPIC_API_KEY=… RECIPE_SEARCH_APP_KEY=<any long random string>
   supabase functions deploy recipe-search --no-verify-jwt
   ```
4. Put the function's address and the app key in `SmartMealPlanner/Data/RecipeSearch.json`:
   `{"url": "https://<project-ref>.supabase.co/functions/v1/recipe-search", "appKey": "<the same random string>"}`.

The function's logic is tested with `node --test supabase/functions/recipe-search/logic.test.ts` (Node 22.6+),
also in the API checks workflow.

## Key decisions

| Decision | Why |
|---|---|
| Weekly per-store fetching instead of daily | Stores change offers once a week; fetching on that day cuts requests to about a dozen a week |
| Recipe search on a server function | Spoonacular gives real, tested recipes; Claude Haiku is fast and cheap for converting them to the app's format. Both keys stay on the server, results are cached, and searches are capped, so an extracted app key can't run up costs |
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
