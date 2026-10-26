# Smart Meal Planner — Summary

**Smart Meal Planner** is a SwiftUI iOS app that plans a week of meals around your diet, routine, household size
and budget, and builds the grocery list from this week's offers at the Dutch supermarkets near you.

## The problem

Planning meals and groceries means juggling what you like to eat, what you can afford and which shop has what on
offer, across a dozen supermarket chains that each start their offer week on a different day. Smart Meal Planner
does that juggling: it plans the week, prices every ingredient from live offers and shelf prices, and keeps one
editable shopping list grouped by store.

## Highlights

- **Weekly plan:** 7 days of breakfast, lunch and dinner from your diet, cuisines, allergies, dislikes and meal
  routine; no dish twice a day or more than twice a week; amounts scaled to the number of people
- **Live offers, fetched smartly:** a grocery database fetches each supermarket once a week, on the day its offer
  week starts (about a dozen requests a week), from the stores within 2 km of your postcode
- **Grocery list:** plan groceries, offers and your own items in one list, filtered by store, with store and overall
  totals; ticking items off tracks weekly spending against your budget
- **Human-made recipes with their sources:** found on Spoonacular for each user's preferences through a free
  Supabase Edge Function, each linked to its original page and a real YouTube video; no built-in samples and no AI
  recipes. Apple's on-device model only suggests which dishes to look up. Offline, the app shows only what it saved
- **Offer alerts:** a weekly local notification when a chosen store's new offers are in
- **Within budget:** cheaper dishes are swapped in until the week fits; it never costs more than the budget plus 10%
- **Quality:** 228 unit tests, 26 UI tests, 57 Python tests and 29 API/security checks, all in CI; every test run is
  recorded in a Google Sheet

## Tech stack

| | |
|---|---|
| Platform | iOS 26, SwiftUI, Swift |
| Architecture | MVVM-inspired, service layer, plain-Swift screen logic for testability |
| Data | Codable JSON, UserDefaults, on-disk cache; grocery feed from a SQLite database built in GitHub Actions |
| Apple frameworks | MapKit (postcode geocoding, nearby stores), Foundation Models (on-device dish ideas), UserNotifications |
| Recipe search | Supabase Edge Function (Deno, TypeScript): Spoonacular API, YouTube Data API |
| Backend | GitHub Actions + Python (stdlib) grocery database, optional Supabase mirror for browsing and edits |
| Testing | Swift Testing, XCUITest, Python unittest, Postman/Newman |
| Design | Figma: [Smart Meal Planner – UI Revamp](https://www.figma.com/design/mCMW5PlNeirvCva8Ns9EAs) |

No third-party app dependencies and no API keys in the app. Recipe search uses Spoonacular and YouTube, whose keys
stay on the server; everything is free.

## Status and roadmap

All features above are working and tested. Possible next steps:

- Current shelf prices for the stores the free source no longer updates (needs a source that isn't blocked and is
  permitted). Albert Heijn offers now come from Open Prices and from deals you add from AH's Bonus page.
- Monthly planning and per-store price comparison in the grocery list
- Nutrition charts with Swift Charts

## Purpose

Built as a portfolio project demonstrating production-ready SwiftUI development, clean architecture and a
real-world data pipeline, with an emphasis on maintainability, testing and honest handling of real data.

**Author:** Nivedhitha Parthasarathy — Senior Mobile Developer (iOS / React Native)
