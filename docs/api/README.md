# Feed API

The app reads files published by the **Grocery database** workflow (`.github/workflows/grocery-feed.yml`) to the
`grocery-feed` branch. They're public, read-only and need no key, and they come from open data only: no supermarket
website is read.

| | |
|---|---|
| Base URL | `https://raw.githubusercontent.com/nivedhitha97/SmartMealPlanner/grocery-feed` |
| Format | JSON (served as `text/plain; charset=utf-8` with `X-Content-Type-Options: nosniff`) |
| Auth | None (public data); writes are refused |
| Cache | `Cache-Control: max-age=300` |
| Licences | Offers and prices: [ODbL](https://opendatacommons.org/licenses/odbl/1-0/), price data © Open Food Facts contributors (`LICENSE.md`). Recipes: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), Wikibooks contributors (`RECIPES-LICENSE.md`) |
| Spec | [`openapi.yaml`](openapi.yaml) (OpenAPI 3.1) |
| Checks | [`SmartMealPlanner.postman_collection.json`](SmartMealPlanner.postman_collection.json) + [`feed.postman_environment.json`](feed.postman_environment.json) |

## Endpoints

### `GET /meta.json`
When the feed was built, when Open Prices is next checked (once a day), how many requests the update job made, the
licence and attribution, and each store's offer-week day.

```json
{
  "generatedAt": "2026-10-26T04:16:02Z",
  "nextUpdateAt": "2026-10-27T05:00:00Z",
  "source": "Open Prices (prices.openfoodfacts.org), shopper-reported open data",
  "attribution": "Price data © Open Food Facts contributors, ODbL",
  "license": "ODbL-1.0",
  "offerCount": 3, "priceCount": 4, "productCount": 61,
  "requests": { "thisRun": 24, "last7Days": 168, "last28Days": 690 },
  "stores": [
    { "id": "jumbo", "name": "Jumbo", "updateDay": "Wednesday", "fetchesOffers": true,
      "lastUpdatedAt": "2026-10-26T04:16:02Z", "nextUpdateAt": "2026-10-27T05:00:00Z", "lastError": null }
  ]
}
```

### `GET /offers.json`
Discounts shoppers reported on Open Prices, as offers for the Monday-to-Sunday week they were seen in, valid now or
starting within a day. There are only a few: it's crowdsourced data. No product photos.

```json
{ "id": "1CF70EBC-C61B-525D-A4E8-CBF38C216617", "storeName": "Albert Heijn", "productName": "Kipfilet",
  "category": "Meat", "offerPrice": 1.99, "regularPrice": 2.79, "unitLabel": "300 g",
  "validUntil": "2026-10-26T22:59:59Z", "observedAt": null, "regionId": "NL", "dealText": "Met klantenkaart",
  "ingredientName": "Chicken Breast", "imageURL": null, "source": "Open Prices" }
```

### `GET /prices.json`
Typical price per 100 g of recipe ingredients, from the shelf prices shoppers reported in the last 90 days (median of
each store's cheapest matching product), plus the cheapest product.

### `GET /recipes.json`
Recipes from the [Wikibooks Cookbook](https://en.wikibooks.org/wiki/Cookbook), imported weekly by `scripts/recipes`.
Each keeps the authors' method, lists the ingredient lines as written, and adds amounts in grams with nutrition per
100 g (USDA FoodData Central, public domain) and the project's own price estimates. Each credits its source.

```json
{ "id": "…", "name": "Potato Curry (Aloo Masala)", "cuisine": "Indian", "servings": 4, "totalMinutes": 20,
  "meals": ["Lunch", "Dinner"],
  "ingredients": [{ "name": "Potatoes", "grams": 1108, "caloriesPer100g": 77, "proteinPer100g": 2.1,
                    "carbsPer100g": 17.5, "fatPer100g": 0.1, "pricePer100g": 0.15 }],
  "steps": ["Heat oil.", "…"], "originalIngredients": ["4 large potatoes, cubed and par-boiled", "…"],
  "sourceName": "Wikibooks Cookbook",
  "sourceURL": "https://en.wikibooks.org/w/index.php?title=Cookbook%3APotato_Curry_%28Aloo_Masala%29&oldid=4615205",
  "authorsURL": "https://en.wikibooks.org/w/index.php?title=Cookbook%3APotato_Curry_%28Aloo_Masala%29&action=history",
  "license": "CC BY-SA 4.0", "licenseURL": "https://creativecommons.org/licenses/by-sa/4.0/",
  "changes": "Adapted for Smart Meal Planner: amounts converted to grams and ingredients named from a standard list.",
  "imageURL": "https://upload.wikimedia.org/…", "imageAuthor": "Thamizhpparithi Maari",
  "imageLicense": "CC BY-SA 4.0", "imageSourceURL": "https://commons.wikimedia.org/wiki/File:…" }
```

### `GET /LICENSE.md`, `GET /RECIPES-LICENSE.md`
The licences and attributions of the offers and prices (ODbL) and of the recipes (CC BY-SA 4.0).

## How clients should download

1. Keep the last good copy of every file.
2. Before `meta.nextUpdateAt`, use that copy without any request: nothing new is published before then.
3. After it, download `meta.json` only; download offers and prices again only if `generatedAt` changed. Recipes
   change weekly: check them at most once a day.
4. On any error, keep using the copy (the app labels it "Offline").

## Functional and security checks (Postman)

The collection checks every file against its schema and runs these tests:

| Check | Expectation |
|---|---|
| Transport | HTTPS; plain HTTP is redirected (301) to HTTPS; HSTS header present |
| Headers | `X-Content-Type-Options: nosniff`, `X-Frame-Options: deny` |
| Secrets | No keys or tokens in any response (Supabase secret keys, JWTs, GitHub tokens, AWS keys, private keys) |
| Integrity | The feed can't be written: `POST`/`PUT` are refused (4xx); unknown files (e.g. `/.env`) return 404 |
| Licences | ODbL with the Open Food Facts credit in meta.json and LICENSE.md; every offer from Open Prices without photos; every recipe credits its Wikibooks revision and authors, CC BY-SA 4.0; photos only with an author and a free licence; RECIPES-LICENSE.md published |
| Data sanity | Feed built within 8 days; regular prices above offer prices; offers not ended; unique ids; prices per 100 g between €0.01 and €10; at least 50 recipes with 3+ ingredients and 2+ steps; under 500 requests a week |
| Supabase mirror | Requests without a key are refused (401) and leak no data; with the public key, row level security returns no rows |

Run them in Postman (import the collection and environment), or from the command line:

```
npx newman run docs/api/SmartMealPlanner.postman_collection.json -e docs/api/feed.postman_environment.json
```

The Supabase checks run only when `supabaseUrl` (and, for the RLS check, `supabasePublishableKey`, the project's
public key, never the `service_role` key) is set in the environment. The **API checks** workflow
(`.github/workflows/api-checks.yml`) runs the collection weekly and when the API files change, with the Supabase URL
from the repository secrets.

GitHub serves the JSON as `text/plain`; with `nosniff` set, browsers can't treat it as script, and the app parses it
as JSON, so this is safe. The Supabase data is reachable only with the `service_role` key, which lives only in the
GitHub secrets.
