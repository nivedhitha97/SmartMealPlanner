# Smart Meal Planner — Summary

**Smart Meal Planner** is a SwiftUI iOS app that plans a week of meals around your diet, routine, household size
and budget, from human-written recipes, and builds the grocery list with the prices shoppers report for Dutch
supermarkets. It uses only open data, and everything you enter stays on your phone.

## The problem

Planning meals and groceries means juggling what you like to eat, what you can afford and what's on offer. Smart
Meal Planner does that juggling: it plans the week from recipes that fit you, prices every ingredient, keeps the week
within budget and keeps one editable shopping list grouped by store.

## Highlights

- **Weekly plan:** 7 days of breakfast, lunch and dinner from your diet, cuisines, allergies, dislikes and meal
  routine; no dish twice a day or more than twice a week; amounts scaled to the number of people
- **Within budget:** cheaper dishes are swapped in until the week fits; it never costs more than the budget plus 10%
- **Human-written, credited recipes:** about 400 meals from the Wikibooks Cookbook (CC BY-SA 4.0), each crediting its
  authors and source revision; nutrition from USDA FoodData Central. AI never writes recipes; Apple's on-device model
  only suggests which dishes to prefer
- **Shopper-reported offers and prices:** from Open Prices (ODbL), checked daily for the stores within 2 km of your
  postcode, plus deals you add yourself
- **Grocery list:** plan groceries, offers and your own items in one list, filtered by store, with store and overall
  totals; ticking items off tracks weekly spending against your budget
- **Private and legal by design:** no accounts, analytics or tracking; open data only, no supermarket website read,
  no logos; privacy policy, terms and data licences in the app
- **Quality:** unit, UI and Python tests and API/licence checks, all in CI; every test run is recorded in a Google
  Sheet (see the [test report](TEST_REPORT.md))

## Tech stack

| | |
|---|---|
| Platform | iOS 26, SwiftUI, Swift |
| Architecture | MVVM-inspired, service layer, plain-Swift screen logic for testability |
| Data | Codable JSON, UserDefaults, on-disk cache; feed (recipes, offers, prices) built in GitHub Actions |
| Apple frameworks | MapKit (postcode geocoding, nearby stores), Foundation Models (on-device dish ideas), UserNotifications |
| Data pipeline | Python (stdlib): Open Prices fetcher and SQLite grocery database; Wikibooks recipe importer with USDA nutrition; optional Supabase mirror |
| Testing | Swift Testing, XCUITest, Python unittest, Postman/Newman |
| Design | Figma: [Smart Meal Planner – UI Revamp](https://www.figma.com/design/mCMW5PlNeirvCva8Ns9EAs) |

No third-party app dependencies, no API keys and no accounts. Every data source is open: Wikibooks (CC BY-SA 4.0),
Wikimedia Commons (free licences), USDA FoodData Central (public domain) and Open Prices (ODbL).

## Status and roadmap

All features above are working and tested. Possible next steps:

- More offers as more shoppers report prices on Open Prices (anyone can contribute)
- Monthly planning and per-store price comparison in the grocery list
- Nutrition charts with Swift Charts

## Purpose

Built as a portfolio project demonstrating production-ready SwiftUI development, clean architecture and a
real-world data pipeline, with an emphasis on maintainability, testing, privacy and honest, properly licensed data.

**Author:** Nivedhitha Parthasarathy — Senior Mobile Developer (iOS / React Native). © 2026, all rights reserved.
