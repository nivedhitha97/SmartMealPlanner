# SmartMealPlanner – iOS (SwiftUI)

[![iOS build](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/swift.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/swift.yml)
[![Grocery database](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/grocery-feed.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/grocery-feed.yml)
[![API checks](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/api-checks.yml/badge.svg?branch=develop)](https://github.com/nivedhitha97/SmartMealPlanner/actions/workflows/api-checks.yml)

**Smart Meal Planner** plans a week of meals around your diet, routine, household and budget, and builds the grocery
list from this week's offers at the Dutch supermarkets near you.

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

## Documentation

| Document | What's in it |
|---|---|
| [Summary](docs/SUMMARY.md) | What the app does, the problem it solves, highlights, tech stack, roadmap |
| [Features](docs/FEATURES.md) | Every feature, screen by screen |
| [Design](docs/DESIGN.md) | Architecture, project structure, grocery database and Supabase mirror, key decisions, design system |
| [API](docs/api/README.md) | The grocery feed API: endpoints, schemas ([OpenAPI](docs/api/openapi.yaml)), download rules, Postman security checks |
| [Test report](docs/TEST_REPORT.md) | Unit, UI, Python and API tests, how to run them, and the Google Sheets test case report |

## Getting started

1. Clone the repository and open `SmartMealPlanner.xcodeproj` in Xcode 26 or later (the app targets iOS 26).
2. Select the `SmartMealPlanner` scheme and run on an iOS Simulator.
3. Run the tests with ⌘U (see the [test report](docs/TEST_REPORT.md)).

No third-party dependencies, paid services or API keys are needed.

## Author

**Nivedhitha Parthasarathy** — Senior Mobile Developer (iOS / React Native)
