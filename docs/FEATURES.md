# Features

## Preferences
- **Diet:** Vegetarian, Non-Vegetarian, Vegan or High Protein
- **People:** 1–10; recipe amounts, grocery quantities and costs scale to it
- **Breakfast:** include breakfast recipes, or granola/muesli only
- **Cuisines** and **exclusions** (dislikes and allergies, comma-separated)
- **Weekly budget** (€20–150)
- **Postcode:** a Dutch postcode gives the region at once and, online, the city, the exact location (street level)
  and the supermarkets within 2 km ("Lidl 100 m · Albert Heijn 150 m · …")
- Saved on the first tap, even before the postcode lookup finishes; unsaved edits survive a visit to Meal routine

## Meal routine
- Breakfast, lunch and dinner each set to **Your usual meals** (fixed), **Home cooked**, **Flexible** or **Outside**

## Weekly plan
- 7 days from today, from recipes that fit the diet, allergies, dislikes and cuisines
- **Variety rules:** a dish is never planned twice on one day, and at most twice a week. When every matching dish has
  reached the limit, the slot shows "No recipe left" and the planner notes suggest adding cuisines
- **Budget card:** estimated groceries against the weekly budget
- **Within budget:** an over-budget week gets cheaper dishes, one swap at a time (the swap that saves most and keeps
  every rule), until it fits; "Your usual meals" are never swapped. If even the cheapest week is over, the planner
  notes say by how much and suggest raising the budget, adding cuisines or setting some meals to Outside
- **Planner notes:** offers used, live prices used, AI recipes added, meals left open
- Day picker, meal slots with recipe photos, weekly nutrition (calories, protein, carbs, fat)
- A grocery card that opens the List tab

## Recipes
- **Found for your preferences, not built in:** [recipe search](DESIGN.md#recipe-search) finds real recipes on
  Spoonacular (up to 6 breakfasts and 12 lunch/dinner dishes) and Claude Haiku adapts them: grams, nutrition, Dutch
  prices and 6–10 detailed steps. Searched again after a week, for variety
- Each says which meals it suits: breakfasts are only planned for breakfast, mains for lunch and dinner. Breakfasts
  may come from any cuisine; lunches and dinners keep to yours
- If recipe search can't be reached, Apple's on-device AI writes recipes (where Apple Intelligence is on)
- Photo, cuisine, ingredients with amounts **for your household** ("For 2 people"), method steps
- **Total, prep and cooking time** ("No cooking" for no-cook dishes)
- **Watch:** opens a real YouTube video of the dish (found by the YouTube Data API), else a YouTube search; in the
  YouTube app, or in Safari when it isn't installed
- **Original:** Spoonacular recipes credit Spoonacular and the site that published them, and link to that page
- **Find this recipe:** on-device AI recipes have no source, so they link to Allerhande and BBC Good Food searches
- Every recipe is labelled "check ingredients for allergens"

## Offers
- This week's offers from Jumbo, Lidl, Dirk, DekaMarkt, Hoogvliet and Poiesz with their real end dates, deals
  ("1+1 gratis", "2 voor €5,00", priced per item) and product photos; price drops at Spar
- **Near me:** only stores within 2 km of your postcode (on by default when known)
- **Store filter** shown as each store's logo badge, plus category filter; "Ending soon" and "More deals"
- **+ on each offer** adds it to the grocery list (shows the quantity; tap again for one more)
- **Albert Heijn Bonus:** AH doesn't let apps read its offers, so the card opens AH's own Bonus page (in the AH app
  when installed, else Safari) and **Add a deal** saves the deals you want, marked "Added by you". They run until
  Sunday (AH's Bonus week) unless you change the date, can be linked to a recipe ingredient so the planner uses the
  price, and stay on the phone. Long-press one to delete it.
- AH discounts that shoppers report on **Open Prices** appear as "Reported on Open Prices", with the ODbL credit
- Freshness line (live, or the saved copy when offline), the next store update, and a **Store updates** list with each
  store's weekly day and whether its data is current; pull to refresh

## Grocery list (List tab)
- One editable list: the plan's groceries, offers you added, and your own items
- Filters: **All**, **Added**, and each store (logo badges); grouped by store with subtotals, the overall total and
  what's left to buy
- Tick items off, edit name/store/price/quantity, delete, add your own; the tab badge shows items left to buy
- **Share:** sends what's left to buy in the current filter as text, by store, with amounts, quantities, prices and
  deals, and the total (WhatsApp, Messages, Notes, email…)
- A new plan replaces only the plan's items; everything you added stays

## Settings
- **Profile:** spent this week (from ticked-off items) against your budget, "Saved €X against your budget" or
  "€X over budget", savings from offers, and the previous three weeks
- **Offer alerts:** a weekly notification on each chosen store's offer day at 09:00 ("New offers at Jumbo"); stores
  near you are chosen by default; tapping an alert opens Offers
- **Appearance:** System, Light or Dark
- Version and build number

## Offline
- The app shows the offers, recipes and plan it last saved; it never shows sample data
- With nothing saved yet, Offers says "No internet connection" with **Try again**, and generating a plan says that
  recipes need an internet connection

## Grocery data (behind the scenes)
- A grocery database fetches each supermarket once a week, on the day its offer week starts, and the app downloads
  only when the feed can have changed. See the [design document](DESIGN.md#grocery-database) and the
  [API document](api/README.md).
- Prices and offers can be browsed and corrected in the Supabase mirror's table editor.
