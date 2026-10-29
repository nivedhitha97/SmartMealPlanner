# SmartMealPlanner – iOS (SwiftUI)

[![iOS build](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/swift.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/swift.yml)
[![Grocery database](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/grocery-feed.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/grocery-feed.yml)
[![API checks](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/api-checks.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/api-checks.yml)

**Smart Meal Planner** plans a week of meals around your diet, routine, household and budget, from human-written
recipes, and builds the grocery list with the prices shoppers report for Dutch supermarkets. It uses only open data,
and everything you enter stays on your phone.

UI designed in Figma: [Smart Meal Planner – UI Revamp](https://www.figma.com/design/mCMW5PlNeirvCva8Ns9EAs)

## Features

### Weekly plan
- **A week of meals in one tap.** Generates 7 days of breakfast, lunch and dinner from recipes that fit your diet,
  cuisines, allergies and dislikes; breakfasts get breakfast dishes.
- **Variety rules.** A dish is never planned twice on one day or more than twice a week; when the recipes run out,
  the slot says so and the notes suggest adding cuisines.
- **Budget card.** The estimated grocery cost against your weekly budget.
- **Kept within budget.** When the week costs more than your budget, the planner swaps dishes for cheaper ones that
  still fit your diet, cuisines and variety rules (your usual meals stay). A week never costs more than the budget plus
  10%: if even the cheapest dishes cost more, meals are left open ("Left open for your budget") and the notes say what
  to change.
- **Planner notes.** What the planner did: offers and reported prices used, where the recipes came from, meals left
  open.
- **Daily meals and nutrition.** Pick a day to see its meals; weekly calories, protein, carbs and fat.

### Recipes
- **Written by people, credited.** Recipes come from the [Wikibooks Cookbook](https://en.wikibooks.org/wiki/Cookbook)
  (CC BY-SA 4.0), with the authors' own method. Each recipe page credits its authors, links to the exact source
  revision and says what was adapted. AI never writes or rewrites a recipe.
- **AI helps choose.** Where Apple Intelligence is on, Apple's on-device model suggests dishes that suit your diet and
  cuisines, and recipes with those names come first.
- **Amounts for your household.** Ingredient amounts in grams, scaled to the number of people you cook for, with the
  original lines as written; nutrition from USDA FoodData Central.
- **Watch.** Opens a YouTube search for the dish (in the YouTube app, or Safari without it).
- **No made-up recipes.** The app ships none of its own; offline it uses the recipes it downloaded before.

### Offline
- **Stored data, never samples.** Offline, the app shows the offers, recipes and plan it last saved. With nothing
  saved yet, it says it needs an internet connection.

### Offers
- **Shopper-reported deals.** Discounts reported by shoppers on [Open Prices](https://prices.openfoodfacts.org/)
  (ODbL), at the supermarkets within 2 km of your postcode. Crowdsourced, so there are only a few.
- **Your own deals.** Add deals from a supermarket's folder or AH's Bonus page (opened in AH's app or Safari); they
  stay on your phone and the planner uses them.
- **Store and category filters**, and **add to list** with the + on an offer.

### Grocery list
- **One editable list.** Your plan's groceries, offers you added and your own items, grouped by store.
- **Totals.** The overall total, each store's subtotal and what's left to buy.
- **Tick off as you shop.** Ticked items count as spent this week; edit, delete or add items any time.
- **Share it.** Send what's left to buy, by store with prices, to WhatsApp, Messages, Notes or email.

### Preferences
- **Diet, people, breakfast, cuisines and exclusions.** Everything the planner needs, saved on the first tap.
- **Weekly budget.** From €20 to €150.
- **Location.** A Dutch postcode gives your city and the supermarkets within 2 km (Apple Maps).
- **Meal routine.** Set breakfast, lunch and dinner to your usual meals, home cooked, flexible or eating out.

### Settings
- **Spending profile.** What you spent this week from ticked-off items, what you saved against your budget, and the
  past three weeks.
- **Offer alerts.** A reminder on each chosen supermarket's offer day.
- **Appearance.** System, light or dark.
- **Share Smart Meal Planner.** Sends the app's link with the iOS share sheet.
- **Privacy and legal.** The privacy policy, terms of use and data sources with their licences.

Every feature in detail, screen by screen: [Features](docs/FEATURES.md).

## Privacy, data and licences

- **Privacy:** no accounts, analytics, ads or tracking; everything you enter stays on your phone
  ([Privacy policy](SmartMealPlanner/Legal/PRIVACY.md)).
- **Terms:** free for personal, non-commercial use; check ingredients for allergens yourself; prices are estimates
  ([Terms of use](SmartMealPlanner/Legal/TERMS.md)).
- **Data sources:** recipes from the Wikibooks Cookbook (CC BY-SA 4.0), photos from Wikimedia Commons (each with its
  own free licence), nutrition from USDA FoodData Central (public domain), offers and prices from Open Prices (ODbL, ©
  Open Food Facts contributors). No supermarket website is read
  ([Data sources and licences](SmartMealPlanner/Legal/CREDITS.md)).
- **Trademarks:** supermarket names belong to their owners and only say where an offer is from. The app shows no
  logos and is not affiliated with any supermarket.
- **This code:** © 2026 Nivedhitha Parthasarathy, all rights reserved ([LICENSE](LICENSE)). The data feed is shared
  under the licences above.

## Documentation

| Document | What's in it |
|---|---|
| [Summary](docs/SUMMARY.md) | What the app does, the problem it solves, highlights, tech stack, roadmap |
| [Features](docs/FEATURES.md) | Every feature, screen by screen |
| [Design](docs/DESIGN.md) | Architecture, project structure, grocery database, recipes, data sources and licences, key decisions, design system |
| [API](docs/api/README.md) | The feed: endpoints, schemas ([OpenAPI](docs/api/openapi.yaml)), licences, download rules, Postman checks |
| [Test report](docs/TEST_REPORT.md) | Unit, UI and Python tests, API checks, how to run them, and the Google Sheets test case report |

## Getting started

1. Clone the repository and open `SmartMealPlanner.xcodeproj` in Xcode 26 or later (the app targets iOS 26).
2. Select the `SmartMealPlanner` scheme and run on an iOS Simulator.
3. Run the tests with ⌘U (see the [test report](docs/TEST_REPORT.md)).

The app needs no API keys or accounts: it downloads the published feed (recipes, offers and prices), which the
**Grocery database** workflow builds from open data.

## Author

**Nivedhitha Parthasarathy** — Senior Mobile Developer (iOS / React Native)
