# Features

## Preferences
- **Diet:** Vegetarian, Non-Vegetarian, Vegan or High Protein
- **People:** 1–10; recipe amounts, grocery quantities and costs scale to it
- **Breakfast:** include breakfast recipes, or granola/muesli only
- **Cuisines** and **exclusions** (dislikes and allergies, comma-separated)
- **Discover new recipes:** add recipes found for these preferences: real Spoonacular recipes adapted by Claude Haiku
  when [recipe search](DESIGN.md#recipe-search) is set up, else written by Apple's on-device AI
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
- **Planner notes:** offers used, live prices used, AI recipes added, meals left open
- Day picker, meal slots with recipe photos, weekly nutrition (calories, protein, carbs, fat)
- A grocery card that opens the List tab

## Recipes
- **50 built-in recipes**, 7–8 per cuisine (Indian, Italian, Dutch, Asian, Mexican, Greek, French), each with 2
  breakfasts and meat, fish, vegetarian and vegan mains, so every diet gets a full week in every cuisine
- Each says which meals it suits: breakfasts are only planned for breakfast, mains for lunch and dinner. When the
  chosen cuisines have no breakfast left, one that fits the diet comes from another cuisine
- Full ingredient lists with real amounts, and 6–9 detailed steps with heat levels and timings
- Photo, cuisine, ingredients with amounts **for your household** ("For 2 people"), method steps
- **Total, prep and cooking time** ("No cooking" for no-cook dishes)
- **Watch:** opens a YouTube search for the recipe in the YouTube app, or in Safari when the app isn't installed
- Cookbook links; AI recipes are labelled "check ingredients for allergens". Spoonacular recipes credit Spoonacular
  and the original site, with a link to the original recipe

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
- Freshness line (live, offline copy, or samples), the next store update, and a **Store updates** list with each
  store's weekly day and whether its data is current; pull to refresh

## Grocery list (List tab)
- One editable list: the plan's groceries, offers you added, and your own items
- Filters: **All**, **Added**, and each store (logo badges); grouped by store with subtotals, the overall total and
  what's left to buy
- Tick items off, edit name/store/price/quantity, delete, add your own; the tab badge shows items left to buy
- A new plan replaces only the plan's items; everything you added stays

## Settings
- **Profile:** spent this week (from ticked-off items) against your budget, "Saved €X against your budget" or
  "€X over budget", savings from offers, and the previous three weeks
- **Offer alerts:** a weekly notification on each chosen store's offer day at 09:00 ("New offers at Jumbo"); stores
  near you are chosen by default; tapping an alert opens Offers
- **Appearance:** System, Light or Dark
- Version and build number

## Grocery data (behind the scenes)
- A grocery database fetches each supermarket once a week, on the day its offer week starts, and the app downloads
  only when the feed can have changed. See the [design document](DESIGN.md#grocery-database) and the
  [API document](api/README.md).
- Prices and offers can be browsed and corrected in the Supabase mirror's table editor.
