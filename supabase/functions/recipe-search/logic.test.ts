// node --test supabase/functions/recipe-search/logic.test.ts  (Node 22.6+ runs TypeScript directly)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  adaptedRecipes,
  cacheKeySource,
  CLAUDE_MODEL,
  claudeRequest,
  compactRecipes,
  parsePreferences,
  RECIPE_TOOL,
  type SpoonRecipe,
  spoonacularQuery,
  youtubeQuery,
  youtubeVideo,
} from "./logic.ts";

const prefs = parsePreferences({
  diet: "Vegetarian", cuisines: ["Indian", "Dutch"], allergies: ["peanut", "kiwi"], dislikes: ["mushroom"], people: 3,
});

const spoon: SpoonRecipe = {
  id: 716426, title: "Cauliflower, Brown Rice, and Vegetable Fried Rice", image: "https://img.spoonacular.com/716426.jpg",
  servings: 4, readyInMinutes: 30, preparationMinutes: -1, cookingMinutes: 20,
  sourceUrl: "https://fullbellysisters.blogspot.com/2012/01/cauliflower-fried-rice.html", sourceName: "Full Belly Sisters",
  cuisines: ["Chinese", "Asian"],
  extendedIngredients: [
    { name: "cauliflower", nameClean: "cauliflower", amount: 1, unit: "head", measures: { metric: { amount: 1, unitShort: "head" } } },
    { name: "brown rice", nameClean: "brown rice", amount: 2, unit: "cups", measures: { metric: { amount: 390, unitShort: "g" } } },
  ],
  nutrition: { ingredients: [{ name: "brown rice", amount: 390, unit: "g", nutrients: [{ name: "Calories", amount: 487 }] }] },
  analyzedInstructions: [{ steps: [{ step: "Rice the cauliflower." }, { step: "Fry with the rice." }] }],
};

const ingredient = (name: string, grams = 200) => ({
  name, grams, caloriesPer100g: 120, proteinPer100g: 4, carbsPer100g: 20, fatPer100g: 2, pricePer100g: 0.4,
});
const claudeSaid = (recipes: unknown[]) => ({ content: [{ type: "tool_use", name: RECIPE_TOOL.name, input: { recipes } }] });
const adapted = (overrides: Record<string, unknown> = {}) => ({
  spoonacularId: 716426, name: "Cauliflower Fried Rice", cuisine: "Asian", servings: 4, prepMinutes: 10, cookMinutes: 20,
  ingredients: [ingredient("Cauliflower", 600), ingredient("Brown Rice", 390)], steps: ["Rice it", "Fry it"], ...overrides,
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

test("recipes are compacted for the prompt", () => {
  const [r] = compactRecipes([spoon]);
  assert.equal(r.preparationMinutes, null, "Spoonacular's -1 means unknown");
  assert.equal(r.ingredients[1].amount, "390 g");
  assert.equal(r.ingredients[1].nutritionForAmount?.calories, 487);
  assert.equal(r.ingredients[0].nutritionForAmount, null);
  assert.deepEqual(r.steps, ["Rice the cauliflower.", "Fry with the rice."]);
});

test("claude request forces the recipe tool with Haiku and includes the preferences", () => {
  const body = claudeRequest(prefs, compactRecipes([spoon]));
  assert.equal(body.model, CLAUDE_MODEL);
  assert.equal(CLAUDE_MODEL, "claude-haiku-5-5");
  assert.deepEqual(body.tool_choice, { type: "tool", name: "save_recipes" });
  const message = body.messages[0].content;
  assert.match(message, /cooking for 3 people/);
  assert.match(message, /Allergies \(never include\): peanut, kiwi/);
  assert.match(message, /716426/);
});

test("adapted recipes get Spoonacular's photo and link, never the model's", () => {
  const [r] = adaptedRecipes(claudeSaid([adapted({ imageURL: "https://evil.example/x.jpg" })]), [spoon], prefs);
  assert.equal(r.imageURL, "https://img.spoonacular.com/716426.jpg");
  assert.equal(r.sourceURL, spoon.sourceUrl);
  assert.equal(r.sourceName, "Full Belly Sisters");
  assert.equal(r.ingredients.length, 2);
});

test("recipes not from Spoonacular, too thin, or with banned ingredients are dropped", () => {
  const recipes = adaptedRecipes(claudeSaid([
    adapted({ spoonacularId: 1 }),
    adapted({ ingredients: [ingredient("Rice")] }),
    adapted({ steps: [] }),
    adapted({ ingredients: [ingredient("Rice"), ingredient("Peanut Sauce", 50)] }),
    adapted({ ingredients: [ingredient("Rice"), ingredient("Button Mushroom", 50)] }),
    adapted(),
  ]), [spoon], prefs);
  assert.equal(recipes.length, 1);
});

test("numbers from the model are clamped to sensible ranges", () => {
  const [r] = adaptedRecipes(claudeSaid([adapted({
    servings: 0, cookMinutes: -5,
    ingredients: [{ ...ingredient("Rice"), pricePer100g: 99, caloriesPer100g: "lots" }, ingredient("Peas")],
  })]), [spoon], prefs);
  assert.equal(r.servings, 1);
  assert.equal(r.cookMinutes, 0);
  assert.equal(r.ingredients[0].pricePer100g, 10);
  assert.equal(r.ingredients[0].caloriesPer100g, 0);
});

test("a response without the tool gives no recipes", () => {
  assert.deepEqual(adaptedRecipes({ content: [{ type: "text" }] }, [spoon], prefs), []);
});

test("breakfasts are searched separately, from any cuisine, and tagged as breakfast", () => {
  const q = spoonacularQuery(prefs, "KEY", "breakfast");
  assert.equal(q.get("type"), "breakfast");
  assert.equal(q.get("cuisine"), null, "breakfasts aren't limited to the user's cuisines");
  assert.equal(q.get("diet"), "vegetarian");
  assert.equal(q.get("intolerances"), "peanut");
  assert.equal(spoonacularQuery(prefs, "KEY").get("type"), "main course");
  assert.match(claudeRequest(prefs, [], "breakfast").system, /breakfasts/);
  const [breakfast] = adaptedRecipes(claudeSaid([adapted()]), [spoon], prefs, "breakfast");
  assert.deepEqual(breakfast.meals, ["Breakfast"]);
  const [main] = adaptedRecipes(claudeSaid([adapted()]), [spoon], prefs);
  assert.deepEqual(main.meals, ["Lunch", "Dinner"]);
  assert.equal(main.youtubeURL, null, "a video is only added after a real YouTube lookup");
});

test("at most 6 breakfasts and 12 mains are kept", () => {
  const many = Array.from({ length: 20 }, () => adapted());
  assert.equal(adaptedRecipes(claudeSaid(many), [spoon], prefs, "breakfast").length, 6);
  assert.equal(adaptedRecipes(claudeSaid(many), [spoon], prefs).length, 12);
});

test("youtube lookups find one real video per recipe", () => {
  const q = youtubeQuery("Chana Masala", "YT");
  assert.equal(q.get("q"), "Chana Masala recipe");
  assert.equal(q.get("type"), "video");
  assert.equal(q.get("maxResults"), "1");
  const video = youtubeVideo({ items: [{ id: { videoId: "dQw4w9WgXcQ" },
    snippet: { title: "Mom&#39;s Chana Masala", channelTitle: "Cook &amp; Eat" } }] });
  assert.deepEqual(video, { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "Mom's Chana Masala",
    channel: "Cook & Eat" });
  assert.equal(youtubeVideo({ items: [] }), null);
  assert.equal(youtubeVideo({ items: [{ id: { videoId: "x/../evil" } }] }), null, "only real video ids");
  assert.equal(youtubeVideo(null), null);
});

test("mains get the cuisine in the user's own words", () => {
  const dutch = parsePreferences({ diet: "Vegetarian", cuisines: ["Dutch", "Indian"] });
  const european: SpoonRecipe = { ...spoon, cuisines: ["European", "German"] };
  const [byClaude] = adaptedRecipes(claudeSaid([adapted({ cuisine: "indian" })]), [european], dutch);
  assert.equal(byClaude.cuisine, "Indian", "Claude's choice, in the user's spelling");
  const [bySource] = adaptedRecipes(claudeSaid([adapted({ cuisine: "German" })]), [european], dutch);
  assert.equal(bySource.cuisine, "Dutch", "Spoonacular's European is the user's Dutch");
  const [breakfast] = adaptedRecipes(claudeSaid([adapted({ cuisine: "American" })]), [european], dutch, "breakfast");
  assert.equal(breakfast.cuisine, "American", "breakfasts keep their own cuisine");
});
