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
│   ├── GroceryDataService.swift   Feed download, disk cache, offline fallback (no sample data), store schedules
│   ├── PostcodeLocationService    Postcode → region, city, coordinates
│   ├── NearbyStoresService        Supermarkets within 2 km (Apple Maps)
│   ├── RecipeDiscovery            The only recipe source: recipe search, the saved recipes offline, the
│   │                              on-device model (Foundation Models) as fallback; cached per preferences
│   ├── RecipeSearchService        Client for the recipe-search function (Spoonacular + Claude Haiku)
│   ├── OfferAlerts                Weekly local notifications per store
│   └── ExternalLinks              YouTube app with Safari fallback
├── ViewModels/                    PlanningViewModel, MealPlanner (filtering, variety rules), WeeklyPlanContent,
│                                  OffersList, ShoppingList (+ purchases, weekly spending), PreferencesForm,
│                                  AppSettings
├── Views/                         MainTabView, SplashView, WeeklyPlanView, RecipeDetailView, WeeklyOffersView,
│                                  GroceryListView, PreferencesView, MealRoutineView, SettingsView
│   └── DesignSystem/              Theme (tokens, components), StoreBadge
└── Data/                          RecipeSearch.json (recipe-search address and app key; empty = off);
                                   UITestRecipes.json, UITestOffers.json: fixed data for UI tests only
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

The app ships no recipes of its own: every recipe is found for the user's preferences.

1. The app sends only the diet, cuisines, allergies, dislikes and number of people (no postcode or budget) to the
   `recipe-search` Supabase Edge Function.
2. The function makes two **Spoonacular** searches side by side: up to 10 breakfasts (any cuisine) and up to 20
   main courses (the user's cuisines), with the diet as a filter, allergies as Spoonacular intolerances (others as
   excluded ingredients) and dislikes excluded, in random order so each week's search brings other dishes.
3. **Claude Haiku** (`claude-haiku-5-5`) puts up to 6 breakfasts and 12 mains in the app's format through a forced
   tool call (one call per course, side by side), labels each main with one of the user's cuisines, and gives every
   ingredient in grams, nutrition per 100 g (from Spoonacular's data where given), Dutch supermarket prices, 6–10
   detailed steps (amounts, heat, timings). It is told to drop any recipe with an allergen or disliked ingredient and never to add ingredients.
4. The function checks the result: only recipes that really came from Spoonacular, numbers clamped to sensible
   ranges, the photo and source link taken from Spoonacular (never from the model), and banned ingredients filtered
   again. With a `YOUTUBE_API_KEY`, each recipe gets a real video from the YouTube Data API (100 of the 10,000 free
   daily units per lookup; a failed lookup leaves a YouTube search link). The app filters a third time, credits
   Spoonacular with a link to the original, and labels the recipe "Adapted by AI from Spoonacular: check
   ingredients for allergens".

The app keeps the recipes for a week, then searches again. If the search can't be reached, it uses the saved recipes
however old (offline it shows what it stored); with none saved, Apple's on-device model writes recipes (when Apple
Intelligence is available) and they link to Allerhande and BBC Good Food searches; otherwise the plan screen says
recipes need an internet connection. There are never sample recipes.

**Keys and cost.** The Spoonacular and Anthropic keys exist only as Supabase secrets. Results are cached for 7 days
per set of preferences (cache hits cost nothing), and new searches are capped per caller (10 a day) and in total
(`RECIPE_SEARCH_DAILY_LIMIT`, default 40 a day). The limit fails closed if the log can't be read. The app key in the
app only keeps out casual callers, since anything shipped in an app can be extracted.

**Setting it up**

1. Get a [Spoonacular API key](https://spoonacular.com/food-api/console) (free plan), an
   [Anthropic API key](https://console.anthropic.com/) and, for real videos, a
   [YouTube Data API key](https://console.cloud.google.com/apis/library/youtube.googleapis.com) (free; optional).
2. In the Supabase SQL editor, run [`supabase/recipe_search_schema.sql`](../supabase/recipe_search_schema.sql).
3. With the [Supabase CLI](https://supabase.com/docs/guides/cli), from the repository root:
   ```bash
   supabase link --project-ref <your-project-ref>
   supabase secrets set SPOONACULAR_API_KEY=… ANTHROPIC_API_KEY=… YOUTUBE_API_KEY=… RECIPE_SEARCH_APP_KEY=<any long random string>
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
| Real store logos, only public-domain ones | The logos are the stores' trademarks, shown only to say which store an offer is from. Only versions marked public domain on Wikimedia Commons are bundled (in the app, not downloaded); stores without one keep a monogram |
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
- **Store badges:** the store's real logo on a white tile, as wide as the logo needs (up to 2.6× its height) and white
  in dark mode too; in lists, badges sit in a fixed-width column so names line up. Stores without a public-domain logo
  (Poiesz, Plus) show their monogram in brand colours

### Store logo sources

Bundled in `SmartMealPlanner/Assets.xcassets/StoreLogos`, all from Wikimedia Commons and marked public domain there
(simple text or shape logos). The logos remain the supermarkets' trademarks.

| Store | Commons file |
|---|---|
| Albert Heijn | [Albert Heijn Logo.svg](https://commons.wikimedia.org/wiki/File:Albert_Heijn_Logo.svg) |
| Aldi | [Aldi Nord 201x logo.svg](https://commons.wikimedia.org/wiki/File:Aldi_Nord_201x_logo.svg) |
| DekaMarkt | [Logo of Dekamarkt.svg](https://commons.wikimedia.org/wiki/File:Logo_of_Dekamarkt.svg) |
| Dirk | [Logo of Dirk.svg](https://commons.wikimedia.org/wiki/File:Logo_of_Dirk.svg) |
| Hoogvliet | [Hoogvliet logo.png](https://commons.wikimedia.org/wiki/File:Hoogvliet_logo.png) |
| Jumbo | [Jumbo Logo.svg](https://commons.wikimedia.org/wiki/File:Jumbo_Logo.svg) |
| Lidl | [Lidl logo.svg](https://commons.wikimedia.org/wiki/File:Lidl_logo.svg) (CC0) |
| Spar | [Spar-logo.svg](https://commons.wikimedia.org/wiki/File:Spar-logo.svg) |
| Vomar | [Logo Vomar.svg](https://commons.wikimedia.org/wiki/File:Logo_Vomar.svg) |
- **Accessibility:** combined elements for cards, decorative icons hidden from VoiceOver, logo chips read the store
  name, 44 pt touch targets
