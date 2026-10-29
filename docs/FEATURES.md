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
- **Never more than budget + 10%:** when even the cheapest dishes cost more than that, meals are left open until the
  week fits, as few as possible (the cheapest dish that is enough to drop, else the dearest); usual meals go last.
  Those slots say "Left open for your budget"
- **Planner notes:** offers and reported prices used, where the recipes came from (with the CC BY-SA credit), meals left open
- Day picker, meal slots with recipe photos, weekly nutrition (calories, protein, carbs, fat)
- A grocery card that opens the List tab

## Recipes
- **Written by people:** every recipe is from the [Wikibooks Cookbook](https://en.wikibooks.org/wiki/Cookbook)
  (CC BY-SA 4.0), imported weekly (about 400 meals). The method is the authors' own text; AI never writes or rewrites
  a recipe
- **Credited:** **About this recipe** says who wrote it (Wikibooks contributors), the licence, and what was adapted
  (amounts converted to grams, ingredients named from a standard list), with links to the exact source revision, the
  authors (page history) and the licence; a photo shows its author and licence (Wikimedia Commons)
- **As written:** the recipe's ingredient lines as the authors wrote them, next to the amounts in grams
- **Chosen for your preferences on the phone:** filtered by diet, allergies and dislikes (nothing is sent anywhere);
  lunches and dinners keep to your cuisines, breakfasts may come from any. Where Apple Intelligence is on, Apple's
  on-device model suggests dishes that suit you and recipes with those names come first
- Each says which meals it suits: breakfasts are only planned for breakfast, mains for lunch and dinner
- Photo (when there's a freely licensed one), cuisine, ingredients with amounts **for your household** ("For 2
  people"), method steps, nutrition from USDA FoodData Central
- **Total time** (and prep and cooking time when known)
- **Watch:** opens a YouTube search for the dish, in the YouTube app or in Safari
- **Original:** opens the recipe's page on Wikibooks
- Every recipe is labelled "By Wikibooks contributors · check ingredients for allergens"
- Offline, the recipes downloaded before are used; recipes saved by earlier versions (Spoonacular, AI) are deleted

## Offers
- Discounts shoppers reported on **Open Prices** for every chain (Albert Heijn, Aldi, DekaMarkt, Dirk, Hoogvliet,
  Jumbo, Lidl, Plus, Poiesz, Spar, Vomar), shown as "Reported on Open Prices", valid for the week they were seen in.
  Crowdsourced, so there are only a few; no product photos. Credit under the offers: "© Open Food Facts contributors,
  ODbL", and that the app isn't affiliated with any supermarket
- **Near me:** only stores within 2 km of your postcode (on by default when known)
- **Store filter** (each store's initials and name) and category filter; "Ending soon" and "More deals"
- **+ on each offer** adds it to the grocery list (shows the quantity; tap again for one more)
- **Albert Heijn Bonus:** the card opens AH's own Bonus page (in the AH app when installed, else Safari) and **Add a
  deal** saves the deals you want from any store's folder, marked "Added by you". They run until Sunday unless you
  change the date, can be linked to a recipe ingredient so the planner uses the price, and stay on the phone.
  Long-press one to delete it
- Freshness line (live, or the saved copy when offline), when prices are checked next (daily), and a **Store updates**
  list with each store's offer-week day; pull to refresh

## Grocery list (List tab)
- One editable list: the plan's groceries, offers you added, and your own items
- Filters: **All**, **Added**, and each store; grouped by store with subtotals, the overall total and
  what's left to buy
- Tick items off, edit name/store/price/quantity, delete, add your own; the tab badge shows items left to buy
- **Share:** sends what's left to buy in the current filter as text, by store, with amounts, quantities, prices and
  deals, and the total (WhatsApp, Messages, Notes, email…)
- A new plan replaces only the plan's items; everything you added stays

## Settings
- **Profile:** spent this week (from ticked-off items) against your budget, "Saved €X against your budget" or
  "€X over budget", savings from offers, and the previous three weeks
- **Offer alerts:** a weekly reminder on each chosen store's offer day at 09:00 ("New offer week at Jumbo"); stores
  near you are chosen by default; tapping an alert opens Offers
- **Appearance:** System, Light or Dark
- **Share Smart Meal Planner:** the app's link (the project page until the app is on the App Store) through the iOS
  share sheet
- **Privacy and legal:** the privacy policy, terms of use, and data sources with their licences and the trademark
  notice, readable offline
- Version and build number

## Offline
- The app shows the offers, recipes and plan it last saved; it never shows sample data
- With nothing saved yet, Offers says "No internet connection" with **Try again**, and generating a plan says that
  recipes need an internet connection

## Privacy
- No accounts, analytics, ads or tracking; everything you enter stays on the phone. Allergies and diet are used only
  on the phone, to filter recipes
- The app downloads the feed (GitHub), recipe photos (Wikimedia) and looks up your postcode (Apple Maps); see the
  [Privacy policy](../SmartMealPlanner/Legal/PRIVACY.md)

## Data behind the scenes
- Open data only, no supermarket website is read: Open Prices is checked once a day, the Wikibooks recipes are
  imported every Monday, and the app downloads only when the feed can have changed. See the
  [design document](DESIGN.md#grocery-database) and the [API document](api/README.md).
- Prices and offers can be browsed and corrected in the Supabase mirror's table editor.
