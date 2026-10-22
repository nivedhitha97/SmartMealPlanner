// node --test supabase/functions/recipe-search/logic.test.ts  (Node 22.6+ runs TypeScript directly)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  cacheKeySource,
  convertedRecipes,
  gramsOf,
  mealsFor,
  parsePreferences,
  type SpoonRecipe,
  spoonacularQuery,
  youtubeQuery,
  youtubeVideo,
} from "./logic.ts";

const prefs = parsePreferences({
  diet: "Vegetarian", cuisines: ["Indian", "Dutch"], allergies: ["peanut", "kiwi"], dislikes: ["mushroom"], people: 3,
});

test("preferences are cleaned and bounded", () => {
  const p = parsePreferences({ diet: "Vegan", cuisines: ["Thai", "a,b;DROP", ""], allergies: "nope", people: 99 });
  assert.deepEqual(p.cuisines, ["Thai", "a b DROP"]);
  assert.deepEqual(p.allergies, []);
  assert.equal(p.people, 10);
  assert.throws(() => parsePreferences({ diet: "Carnivore" }), /diet must be one of/);
  assert.throws(() => parsePreferences(null), /JSON object/);
});

test("cache key ignores order and case", () => {
  const a = parsePreferences({ diet: "Vegan", cuisines: ["Thai", "Indian"], allergies: ["Soy"] });
  const b = parsePreferences({ diet: "Vegan", cuisines: ["indian", "thai"], allergies: ["soy"] });
  assert.equal(cacheKeySource(a), cacheKeySource(b));
});

test("spoonacular query carries diet, cuisines, intolerances and exclusions", () => {
  const q = spoonacularQuery(prefs, "KEY");
  assert.equal(q.get("diet"), "vegetarian");
  assert.equal(q.get("cuisine"), "Indian,European");
  assert.equal(q.get("intolerances"), "peanut");
  assert.equal(q.get("excludeIngredients"), "mushroom,kiwi");
  assert.equal(q.get("addRecipeNutrition"), "true");
  assert.equal(spoonacularQuery(parsePreferences({ diet: "High Protein" }), "K").get("minProtein"), "25");
  assert.equal(spoonacularQuery(parsePreferences({ diet: "Non-Vegetarian" }), "K").get("diet"), null);
});

test("dish ideas from the app are cleaned and limited", () => {
  const p = parsePreferences({ diet: "Vegan", ideas: ["Chana Masala", "Dal; DROP TABLE", "", 42, ...Array(12).fill("Soup")] });
  assert.deepEqual(p.ideas.slice(0, 2), ["Chana Masala", "Dal DROP TABLE"]);
  assert.equal(p.ideas.length, 8, "at most 8 searches per request");
  assert.deepEqual(parsePreferences({ diet: "Vegan" }).ideas, [], "ideas are optional");
});

test("a dish idea is searched by name, with the same diet, allergies and dislikes", () => {
  const q = spoonacularQuery(prefs, "KEY", "main", "Palak Paneer");
  assert.equal(q.get("query"), "Palak Paneer");
  assert.equal(q.get("number"), "2");
  assert.equal(q.get("sort"), null, "most relevant first");
  assert.equal(q.get("type"), null, "the dish decides whether it is a breakfast or a main");
  assert.equal(q.get("cuisine"), null);
  assert.equal(q.get("diet"), "vegetarian");
  assert.equal(q.get("intolerances"), "peanut");
  assert.equal(q.get("excludeIngredients"), "mushroom,kiwi");
});

test("breakfasts are searched from any cuisine; mains in the user's cuisines", () => {
  const breakfast = spoonacularQuery(prefs, "KEY", "breakfast");
  assert.equal(breakfast.get("type"), "breakfast");
  assert.equal(breakfast.get("cuisine"), null);
  assert.equal(breakfast.get("sort"), "random", "different dishes each week");
  assert.equal(spoonacularQuery(prefs, "KEY").get("type"), "main course");
});

test("Spoonacular's dish types decide which meals a recipe suits", () => {
  const recipe = (dishTypes?: string[]) => ({ id: 1, title: "x", dishTypes });
  assert.deepEqual(mealsFor(recipe(["breakfast", "brunch", "morning meal"]), "main"), ["Breakfast"]);
  assert.deepEqual(mealsFor(recipe(["lunch", "main course", "dinner"]), "breakfast"), ["Lunch", "Dinner"]);
  assert.deepEqual(mealsFor(recipe(["brunch", "lunch"]), "main"), ["Breakfast", "Lunch", "Dinner"]);
  assert.deepEqual(mealsFor(recipe([]), "breakfast"), ["Breakfast"], "no types: the search it came from");
  assert.deepEqual(mealsFor(recipe(undefined), "main"), ["Lunch", "Dinner"]);
});

test("youtube lookups find one real video per recipe", () => {
  const q = youtubeQuery("Chana Masala", "YT");
  assert.equal(q.get("q"), "Chana Masala recipe");
  assert.equal(q.get("type"), "video");
  assert.equal(q.get("maxResults"), "5");
  const video = youtubeVideo({ items: [{ id: { videoId: "dQw4w9WgXcQ" },
    snippet: { title: "Mom&#39;s Chana Masala", channelTitle: "Cook &amp; Eat" } }] });
  assert.deepEqual(video, { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "Mom's Chana Masala",
    channel: "Cook & Eat" });
  assert.equal(youtubeVideo({ items: [] }), null);
  assert.equal(youtubeVideo({ items: [{ id: { videoId: "x/../evil" } }] }), null, "only real video ids");
  assert.equal(youtubeVideo(null), null);
});

test("youtube videos fit the diet and aren't shorts", () => {
  assert.equal(youtubeQuery("Couscous Biryani", "YT", "Vegetarian").get("q"), "vegetarian Couscous Biryani recipe");
  assert.equal(youtubeQuery("Vegan Chana Masala", "YT", "Vegan").get("q"), "Vegan Chana Masala recipe");
  assert.equal(youtubeQuery("Couscous Biryani", "YT", "Non-Vegetarian").get("q"), "Couscous Biryani recipe");

  const item = (videoId: string, title: string) => ({ id: { videoId }, snippet: { title, channelTitle: "C" } });
  const results = { items: [
    item("aaaaaaaaaaa", "Chicken Couscous Biryani"),
    item("bbbbbbbbbbb", "Couscous Biryani #shorts"),
    item("ccccccccccc", "Easy Couscous Biryani"),
  ] };
  assert.equal(youtubeVideo(results, "Couscous Biryani", "Vegetarian")?.title, "Easy Couscous Biryani");
  assert.equal(youtubeVideo(results, "Couscous Biryani", "Non-Vegetarian")?.title, "Chicken Couscous Biryani");
  assert.equal(youtubeVideo({ items: [item("bbbbbbbbbbb", "Palak Paneer #shorts")] }, "Palak Paneer")?.title,
    "Palak Paneer #shorts", "a short when there's nothing else");
  const eggs = { items: [item("aaaaaaaaaaa", "Egg Curry"), item("ccccccccccc", "Tofu Curry")] };
  assert.equal(youtubeVideo(eggs, "Boiled Egg Curry", "Vegetarian")?.title, "Egg Curry", "eggs are vegetarian");
  assert.equal(youtubeVideo(eggs, "Tofu Curry", "Vegan")?.title, "Tofu Curry");
  assert.equal(youtubeVideo({ items: [item("aaaaaaaaaaa", "Chicken Curry")] }, "Curry", "Vegan"), null,
    "no video rather than a meat one");
});

// ---- Into the app's format ----

const shakshuka: SpoonRecipe = {
  id: 1001, title: "Easy Shakshuka", image: "https://img.spoonacular.com/1001.jpg", servings: 2,
  readyInMinutes: 30, preparationMinutes: -1, cookingMinutes: -1, pricePerServing: 150,
  sourceUrl: "https://example-food-blog.com/shakshuka", sourceName: "Example Food Blog", cuisines: ["Middle Eastern"],
  extendedIngredients: [
    { id: 1, name: "eggs", nameClean: "egg", amount: 4, unit: "", measures: { metric: { amount: 4, unitShort: "" } } },
    { id: 2, name: "canned tomatoes", nameClean: "canned tomatoes", amount: 1, unit: "can",
      measures: { metric: { amount: 400, unitShort: "g" } } },
    { id: 3, name: "olive oil", nameClean: "olive oil", amount: 1, unit: "tbsp", measures: { metric: { amount: 1, unitShort: "Tbsp" } } },
    { id: 4, name: "onion", nameClean: "onion", amount: 1, unit: "large", measures: { metric: { amount: 1, unitShort: "large" } } },
  ],
  nutrition: { ingredients: [
    { id: 1, name: "eggs", nutrients: [{ name: "Calories", amount: 286 }, { name: "Protein", amount: 25.2 }] },
    { id: 2, name: "canned tomatoes", nutrients: [{ name: "Calories", amount: 128 }, { name: "Carbohydrates", amount: 28 }] },
    { id: 3, name: "olive oil", nutrients: [{ name: "Calories", amount: 119 }, { name: "Fat", amount: 13.5 }] },
  ] },
  analyzedInstructions: [{ steps: [{ step: "Fry the onion in the oil for 5 minutes." }, { step: "Add the tomatoes and simmer for 10 minutes." },
    { step: "Make 4 wells, crack in the eggs, cover and cook for 6 minutes." }] }],
};

test("ingredient amounts become grams", () => {
  assert.equal(gramsOf({ amount: 400, measures: { metric: { amount: 400, unitShort: "g" } } }), 400);
  assert.equal(gramsOf({ measures: { metric: { amount: 2, unitShort: "Tbsps" } } }), 30);
  assert.equal(gramsOf({ measures: { metric: { amount: 1, unitShort: "cup" } } }), 240);
  assert.equal(gramsOf({ nameClean: "egg", measures: { metric: { amount: 3, unitShort: "" } } }), 150, "3 eggs");
  assert.equal(gramsOf({ nameClean: "onion", measures: { metric: { amount: 1, unitShort: "large" } } }), 125);
  assert.equal(gramsOf({ nameClean: "something", measures: { metric: { amount: 2, unitShort: "servings" } } }), 200);
  assert.equal(gramsOf({ measures: { metric: { amount: 0, unitShort: "g" } } }), 0);
});

test("Spoonacular's recipes are put in the app's format unchanged", () => {
  const veg = parsePreferences({ diet: "Vegetarian", cuisines: [], people: 2 });
  const [r] = convertedRecipes([shakshuka], veg, "breakfast");
  assert.equal(r.name, "Easy Shakshuka");
  assert.deepEqual(r.meals, ["Breakfast"]);
  assert.equal(r.cuisine, "Middle Eastern");
  assert.deepEqual(r.ingredients.map((i) => [i.name, i.grams]), [["Egg", 200], ["Canned Tomatoes", 400], ["Olive Oil", 15], ["Onion", 125]]);
  assert.equal(r.ingredients[0].caloriesPer100g, 143, "286 kcal for 200 g of egg");
  assert.equal(r.ingredients[0].proteinPer100g, 12.6);
  assert.equal(r.ingredients[2].fatPer100g, 90, "olive oil: 13.5 g fat in 15 g");
  assert.equal(r.ingredients[3].caloriesPer100g, 0, "no nutrition given: zero, not invented");
  assert.equal(r.ingredients[0].pricePer100g, 0.37, "€2.76 (150 US cents × 2 × 0.92) over 740 g");
  assert.deepEqual([r.prepMinutes, r.cookMinutes], [9, 21], "from the 30 minutes ready time");
  assert.deepEqual(r.steps, shakshuka.analyzedInstructions![0].steps!.map((x) => x.step), "the original method, word for word");
  assert.equal(r.sourceURL, "https://example-food-blog.com/shakshuka");
  assert.equal(r.sourceName, "Example Food Blog");
  assert.equal(r.imageURL, "https://img.spoonacular.com/1001.jpg");
  assert.equal(r.youtubeURL, null, "a video is only added after a real YouTube lookup");
});

test("recipes breaking an allergy or dislike, or without a method, are left out", () => {
  assert.deepEqual(convertedRecipes([shakshuka], parsePreferences({ diet: "Vegetarian", allergies: ["egg"] })), []);
  assert.deepEqual(convertedRecipes([shakshuka], parsePreferences({ diet: "Vegetarian", dislikes: ["onion"] })), []);
  const noSteps: SpoonRecipe = { ...shakshuka, analyzedInstructions: [] };
  assert.deepEqual(convertedRecipes([noSteps], parsePreferences({ diet: "Vegetarian" })), []);
});

test("at most 6 breakfasts and 12 mains are kept", () => {
  const many = Array.from({ length: 20 }, (_, i) => ({ ...shakshuka, id: i }));
  const veg = parsePreferences({ diet: "Vegetarian" });
  assert.equal(convertedRecipes(many, veg, "breakfast").length, 6);
  assert.equal(convertedRecipes(many, veg).length, 12);
});

test("mains get the cuisine in the user's own words", () => {
  const dutch = parsePreferences({ diet: "Vegetarian", cuisines: ["Dutch", "Indian"] });
  const [european] = convertedRecipes([{ ...shakshuka, cuisines: ["European", "German"] }], dutch);
  assert.equal(european.cuisine, "Dutch", "Spoonacular's European is the user's Dutch");
  const [indian] = convertedRecipes([{ ...shakshuka, cuisines: ["Indian"] }], dutch);
  assert.equal(indian.cuisine, "Indian");
  const [breakfast] = convertedRecipes([{ ...shakshuka, cuisines: ["American"] }], dutch, "breakfast");
  assert.equal(breakfast.cuisine, "American", "breakfasts keep their own cuisine");
});
