# Grocery feed API

The app reads three JSON files published by the **Grocery database** workflow (`.github/workflows/grocery-feed.yml`)
to the `grocery-feed` branch. They're public, read-only and need no key.

| | |
|---|---|
| Base URL | `https://raw.githubusercontent.com/nivedhitha97/SmartMealPlanner/grocery-feed` |
| Format | JSON (served as `text/plain; charset=utf-8` with `X-Content-Type-Options: nosniff`) |
| Auth | None (public data); writes are refused |
| Cache | `Cache-Control: max-age=300` |
| Spec | [`openapi.yaml`](openapi.yaml) (OpenAPI 3.1) |
| Checks | [`SmartMealPlanner.postman_collection.json`](SmartMealPlanner.postman_collection.json) + [`feed.postman_environment.json`](feed.postman_environment.json) |

## Endpoints

### `GET /meta.json`
When the feed was built, when it next changes, how many requests the update job made, and each store's schedule.

```json
{
  "generatedAt": "2026-10-15T13:28:12Z",
  "nextUpdateAt": "2026-10-18T04:00:00Z",
  "offerCount": 615, "priceCount": 18, "productCount": 107314,
  "requests": { "thisRun": 2, "last7Days": 13, "last28Days": 13 },
  "stores": [
    { "id": "jumbo", "name": "Jumbo", "updateDay": "Wednesday", "fetchesOffers": true,
      "lastUpdatedAt": "2026-10-15T13:28:12Z", "nextUpdateAt": "2026-10-21T04:00:00Z",
      "pricesChangedAt": "2026-10-15T13:28:12Z", "pricesAreCurrent": true, "lastError": null }
  ]
}
```

### `GET /offers.json`
This week's offers, valid now or starting within a day: recipe ingredients first, then by end date and biggest saving.
Prices are per item (multi-buy deals are divided per item).

```json
{ "id": "1CF70EBC-C61B-525D-A4E8-CBF38C216617", "storeName": "Poiesz", "productName": "Zalmfilet zonder huid",
  "category": "Fish", "offerPrice": 5.0, "regularPrice": 5.99, "unitLabel": "pakje à 175 gram",
  "validUntil": "2026-10-17T21:59:59Z", "observedAt": null, "regionId": "NL", "dealText": null,
  "ingredientName": "Salmon Fillet", "imageURL": "https://files.poiesz-supermarkten.nl/…?width=300&mode=fill" }
```

### `GET /prices.json`
Typical current price per 100 g of each recipe ingredient (median of each store's cheapest matching product, from
stores whose shelf prices are current), plus the cheapest product.

```json
{ "ingredientName": "Arborio Rice", "pricePer100g": 0.535, "cheapestStore": "Jumbo",
  "cheapestProduct": "Jumbo Risotto rijst Arborio 500 g", "cheapestPrice": 1.99, "cheapestSize": "500 g",
  "cheapestPricePer100g": 0.398, "storeCount": 2, "productCount": 6 }
```

## How clients should download

1. Keep the last good copy of all three files.
2. Before `meta.nextUpdateAt`, use that copy without any request: nothing new is published before then.
3. After it, download `meta.json` only; download offers and prices again only if `generatedAt` changed.
4. On any error, keep using the copy (the app labels it "Offline").

## Functional and security checks (Postman)

The collection checks every file against its schema and runs these security tests:

| Check | Expectation |
|---|---|
| Transport | HTTPS; plain HTTP is redirected (301) to HTTPS; HSTS header present |
| Headers | `X-Content-Type-Options: nosniff`, `X-Frame-Options: deny` |
| Secrets | No keys or tokens in any response (Supabase secret keys, JWTs, GitHub tokens, AWS keys, private keys) |
| Integrity | The feed can't be written: `POST`/`PUT` are refused (4xx); unknown files (e.g. `/.env`) return 404 |
| Data sanity | Feed built within 8 days; regular prices above offer prices; offers not ended; unique ids; prices per 100 g between €0.01 and €10; under 100 supermarket requests a week |
| Supabase mirror | Requests without a key are refused (401) and leak no data; with the public key, row level security returns no rows |

Run them in Postman (import the collection and environment), or from the command line:

```
npx newman run docs/api/SmartMealPlanner.postman_collection.json -e docs/api/feed.postman_environment.json
```

The Supabase checks run only when `supabaseUrl` (and, for the RLS check, `supabasePublishableKey`, the project's
public key, never the `service_role` key) is set in the environment. The **API checks** workflow
(`.github/workflows/api-checks.yml`) runs the collection weekly and when the API files change, with the Supabase URL
from the repository secrets.

**Findings (last run: all 29 checks passed):** GitHub serves the JSON as `text/plain`; with `nosniff` set, browsers
can't treat it as script, and the app parses it as JSON, so this is safe. The Supabase data is reachable only with
the `service_role` key, which lives only in the GitHub secrets.
