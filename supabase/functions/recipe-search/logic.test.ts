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
