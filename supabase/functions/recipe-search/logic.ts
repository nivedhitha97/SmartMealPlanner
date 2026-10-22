// Recipe search: genuine, human-made recipes from Spoonacular (published on real recipe sites), put in the app's format
// without changing them: amounts in grams, nutrition per 100 g, the original method. No recipe is written or
// rewritten by AI; the app's on-device model may only suggest dish names to search for (`ideas`). Pure functions
// only, so they can be tested without Deno or the network (node --test logic.test.ts); index.ts does the I/O.

/** A week needs breakfasts as well as lunches and dinners; each is a separate Spoonacular search. */
export type Course = "breakfast" | "main";
export const COURSES: Record<Course, { type: string; results: number; max: number; meals: string[]; cuisines: boolean }> = {
  // Breakfasts aren't limited to the user's cuisines: few cuisines have many.
  breakfast: { type: "breakfast", results: 10, max: 6, meals: ["Breakfast"], cuisines: false },
  main: { type: "main course", results: 20, max: 12, meals: ["Lunch", "Dinner"], cuisines: true },
};
/** Dish ideas searched one by one, and how many recipes each may bring. */
export const MAX_IDEAS = 8;
export const RESULTS_PER_IDEA = 2;

export type Preferences = {
  diet: string;
  cuisines: string[];
  allergies: string[];
  dislikes: string[];
  people: number;
  /** Dish names the app's on-device AI suggested for these preferences, e.g. "Chana Masala"; may be empty. */
  ideas: string[];
};

export type AppIngredient = {
  name: string;
  grams: number;
  caloriesPer100g: number;
  proteinPer100g: number;
  carbsPer100g: number;
  fatPer100g: number;
  pricePer100g: number;
};

export type AppRecipe = {
  spoonacularId: number;
  name: string;
  cuisine: string;
  servings: number;
  prepMinutes: number;
  cookMinutes: number;
  ingredients: AppIngredient[];
  steps: string[];
  meals: string[];
  imageURL: string | null;
  sourceURL: string | null;
  sourceName: string | null;
  /** A real YouTube video for the dish (found with the YouTube Data API), or null to fall back to a search. */
  youtubeURL: string | null;
  youtubeTitle: string | null;
  youtubeChannel: string | null;
};

// ---- Request validation ----

const DIETS = ["Vegetarian", "Non-Vegetarian", "Vegan", "High Protein"];

/** The app's request, cleaned up; throws a message for the client when it isn't usable. */
export function parsePreferences(body: unknown): Preferences {
  if (typeof body !== "object" || body === null) throw new Error("Expected a JSON object");
  const b = body as Record<string, unknown>;
  const diet = typeof b.diet === "string" && DIETS.includes(b.diet) ? b.diet : null;
  if (!diet) throw new Error(`diet must be one of ${DIETS.join(", ")}`);
  const people = Number(b.people ?? 1);
  return {
    diet,
    cuisines: words(b.cuisines),
    allergies: words(b.allergies),
    dislikes: words(b.dislikes),
    people: Number.isFinite(people) ? Math.min(10, Math.max(1, Math.round(people))) : 1,
    ideas: words(b.ideas).slice(0, MAX_IDEAS),
  };
}

/** Up to 10 short, plain words: no commas or control characters can reach the Spoonacular query or the prompt. */
function words(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((v): v is string => typeof v === "string")
    .map((v) => v.replace(/[^\p{L}\p{N} '-]/gu, " ").replace(/\s+/g, " ").trim().slice(0, 40))
    .filter((v) => v.length > 0)
    .slice(0, 10);
}

/** The same preferences always give the same key, so cached results are reused (order and case don't matter). */
export function cacheKeySource(p: Preferences): string {
  const norm = (list: string[]) => list.map((v) => v.toLowerCase()).sort().join(",");
  return [p.diet, norm(p.cuisines), norm(p.allergies), norm(p.dislikes)].join("|");
}

// ---- Spoonacular ----

// Allergies Spoonacular understands as intolerances; anything else is excluded by ingredient name.
const INTOLERANCES: Record<string, string> = {
  dairy: "dairy", milk: "dairy", lactose: "dairy", cheese: "dairy",
  egg: "egg", eggs: "egg",
  gluten: "gluten", wheat: "wheat", grain: "grain",
  peanut: "peanut", peanuts: "peanut",
  "tree nut": "tree nut", "tree nuts": "tree nut", nut: "tree nut", nuts: "tree nut",
  seafood: "seafood", fish: "seafood", shellfish: "shellfish", shrimp: "shellfish",
  sesame: "sesame", soy: "soy", soya: "soy", sulfite: "sulfite",
};

// The app's cuisines in Spoonacular's names.
const CUISINES: Record<string, string> = {
  dutch: "European", indian: "Indian", italian: "Italian", asian: "Asian", chinese: "Chinese",
  japanese: "Japanese", thai: "Thai", mexican: "Mexican", greek: "Greek", french: "French",
  mediterranean: "Mediterranean", "middle eastern": "Middle Eastern", spanish: "Spanish", korean: "Korean",
  vietnamese: "Vietnamese", american: "American", british: "British", german: "German",
};

/** A search for one course, or, with `idea`, for that dish (by name, most relevant first). The diet, allergies and
 *  dislikes always apply, so an idea can never bring a recipe that breaks them. */
export function spoonacularQuery(p: Preferences, apiKey: string, course: Course = "main", idea?: string): URLSearchParams {
  const intolerances = new Set<string>();
  const exclude = new Set<string>(p.dislikes.map((d) => d.toLowerCase()));
  for (const allergy of p.allergies) {
    const known = INTOLERANCES[allergy.toLowerCase()];
    if (known) intolerances.add(known);
    else exclude.add(allergy.toLowerCase());
  }
  const query = new URLSearchParams({
    apiKey,
    type: COURSES[course].type,
    instructionsRequired: "true",
    addRecipeInformation: "true",
    fillIngredients: "true",
    addRecipeNutrition: "true",
    sort: "random", // a different selection each time the cache expires, for variety week to week
    number: String(COURSES[course].results),
  });
  if (p.diet === "Vegetarian") query.set("diet", "vegetarian");
  if (p.diet === "Vegan") query.set("diet", "vegan");
  if (p.diet === "High Protein") query.set("minProtein", "25");
  const cuisines = [...new Set(p.cuisines.map((c) => CUISINES[c.toLowerCase()]).filter(Boolean))];
  if (cuisines.length && COURSES[course].cuisines) query.set("cuisine", cuisines.join(","));
  if (intolerances.size) query.set("intolerances", [...intolerances].join(","));
  if (exclude.size) query.set("excludeIngredients", [...exclude].join(","));
  if (idea) {
    query.set("query", idea);
    query.set("number", String(RESULTS_PER_IDEA));
    query.delete("sort");    // the best matches for the dish, not random ones
    query.delete("type");    // the dish decides: an idea can be a breakfast or a main
    query.delete("cuisine"); // the idea already fits the cuisines
  }
  return query;
}

type Nutrient = { name?: string; amount?: number };
type SpoonIngredient = {
  id?: number; name?: string; nameClean?: string | null; amount?: number; unit?: string;
  measures?: { metric?: { amount?: number; unitShort?: string } };
};
export type SpoonRecipe = {
  id: number; title: string; image?: string; servings?: number; readyInMinutes?: number;
  preparationMinutes?: number | null; cookingMinutes?: number | null; sourceUrl?: string; sourceName?: string;
  spoonacularSourceUrl?: string; cuisines?: string[]; dishTypes?: string[]; pricePerServing?: number;
  extendedIngredients?: SpoonIngredient[];
  nutrition?: { ingredients?: { id?: number; name?: string; amount?: number; unit?: string; nutrients?: Nutrient[] }[] };
  analyzedInstructions?: { steps?: { step?: string }[] }[];
};

function positive(value: number | null | undefined): number | null {
  return typeof value === "number" && value > 0 ? value : null;
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

/** The cuisine in the user's own words ("Dutch", not Spoonacular's "European"), so the app keeps lunches and dinners
 *  to the cuisines they chose. The search was filtered by those cuisines, so every main belongs to one of them. */
function cuisineFor(source: SpoonRecipe, p: Preferences, course: Course): string {
  const fallback = text(null, source.cuisines?.[0] ?? "International");
  if (course === "breakfast" || !p.cuisines.length) return fallback;
  const said = fallback.toLowerCase();
  const sourceCuisines = (source.cuisines ?? []).map((c) => c.toLowerCase());
  return p.cuisines.find((c) => c.toLowerCase() === said)
    ?? p.cuisines.find((c) => sourceCuisines.includes((CUISINES[c.toLowerCase()] ?? c).toLowerCase()))
    ?? p.cuisines[0];
}

function text(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 120) : fallback;
}

function clamp(value: unknown, min: number, max: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : min;
}

function clampInt(value: unknown, min: number, max: number, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.round(n))) : fallback;
}

function https(url: string | undefined | null): string | null {
  return typeof url === "string" && url.startsWith("https://") ? url : null;
}

// ---- Into the app's format ----
// Spoonacular gives each ingredient's metric amount and its nutrition for that amount, the original method and a price
// per serving, so recipes can be put in the app's format without changing them.

const UNIT_GRAMS: Record<string, number> = {
  g: 1, gram: 1, grams: 1, kg: 1000, mg: 0.001, ml: 1, milliliter: 1, milliliters: 1, l: 1000, liter: 1000,
  liters: 1000, tsp: 5, tsps: 5, teaspoon: 5, teaspoons: 5, tbsp: 15, tbsps: 15, tablespoon: 15, tablespoons: 15,
  cup: 240, cups: 240, oz: 28.35, ounce: 28.35, ounces: 28.35, lb: 453.6, lbs: 453.6, pound: 453.6, pounds: 453.6,
  pinch: 0.4, pinches: 0.4, dash: 0.6, dashes: 0.6, clove: 4, cloves: 4, slice: 30, slices: 30, can: 400, cans: 400,
  stick: 113, sticks: 113, handful: 30, handfuls: 30, bunch: 50, bunches: 50, sprig: 1, sprigs: 1, leaf: 0.5, leaves: 0.5,
};
const SIZE: Record<string, number> = { small: 0.75, medium: 1, large: 1.25 };
// Typical weights of one piece, for "2 eggs", "1 large onion"; anything else counts as 100 g.
const PIECE_GRAMS: [RegExp, number][] = [
  [/egg/, 50], [/garlic/, 4], [/onion|shallot/, 100], [/tomato/, 120], [/potato/, 170], [/lemon|lime/, 80],
  [/carrot/, 60], [/bell pepper|capsicum/, 150], [/avocado/, 170], [/apple|pear|orange/, 150], [/banana/, 120],
  [/zucchini|courgette|cucumber|eggplant|aubergine/, 200], [/chicken breast/, 170], [/tortilla/, 45], [/chili|chilli/, 15],
];
const USD_TO_EUR = 0.92;

/** Grams of an ingredient from its metric amount, else from typical piece weights. */
export function gramsOf(ingredient: SpoonIngredient): number {
  const metric = ingredient.measures?.metric;
  const amount = Number(metric?.amount ?? ingredient.amount ?? 0);
  const unit = String(metric?.unitShort ?? ingredient.unit ?? "").toLowerCase().replace(/\.$/, "").trim();
  if (!(amount > 0)) return 0;
  if (UNIT_GRAMS[unit] !== undefined) return amount * UNIT_GRAMS[unit];
  const name = String(ingredient.nameClean || ingredient.name || "").toLowerCase();
  const piece = PIECE_GRAMS.find(([pattern]) => pattern.test(name))?.[1] ?? 100;
  return amount * piece * (SIZE[unit] ?? 1);
}

/** Which meals a recipe suits, from Spoonacular's dish types ("breakfast", "main course", …), else from the search. */
export function mealsFor(source: SpoonRecipe, course: Course): string[] {
  const types = (source.dishTypes ?? []).map((t) => t.toLowerCase());
  const meals: string[] = [];
  if (types.some((t) => ["breakfast", "brunch", "morning meal"].includes(t))) meals.push("Breakfast");
  if (types.some((t) => ["lunch", "main course", "main dish", "dinner", "soup", "salad"].includes(t))) meals.push("Lunch", "Dinner");
  return meals.length ? meals : COURSES[course].meals;
}

/** Spoonacular's recipes in the app's format, unchanged in substance: their own ingredients, amounts (in grams),
 *  nutrition and method. Recipes with an allergen or disliked ingredient, or without a method, are left out. */
export function convertedRecipes(sources: SpoonRecipe[], p: Preferences, course: Course = "main"): AppRecipe[] {
  const banned = [...p.allergies, ...p.dislikes].map((w) => w.toLowerCase()).filter((w) => w.length > 2);
  const result: AppRecipe[] = [];
  for (const source of sources) {
    const nutrition = new Map((source.nutrition?.ingredients ?? []).map((n) => [n.id, n]));
    const byName = new Map<string, AppIngredient>();
    let totalGrams = 0;
    for (const item of source.extendedIngredients ?? []) {
      const grams = gramsOf(item);
      const name = titleCase(item.nameClean || item.name || "");
      if (!name || grams < 1) continue;
      const n = nutrition.get(item.id);
      const per100 = (key: string, max: number) => {
        const value = n?.nutrients?.find((x) => x.name === key)?.amount;
        return value === undefined ? 0 : clamp(value / grams * 100, 0, max);
      };
      const existing = byName.get(name);
      if (existing) { existing.grams += Math.round(grams); totalGrams += grams; continue; }
      byName.set(name, {
        name, grams: Math.round(grams), caloriesPer100g: Math.round(per100("Calories", 900)),
        proteinPer100g: round(per100("Protein", 100)), carbsPer100g: round(per100("Carbohydrates", 100)),
        fatPer100g: round(per100("Fat", 100)), pricePer100g: 0,
      });
      totalGrams += grams;
    }
    const ingredients = [...byName.values()].slice(0, 15);
    const steps = (source.analyzedInstructions ?? []).flatMap((a) => a.steps ?? [])
      .map((x) => String(x.step ?? "").trim().slice(0, 500)).filter(Boolean).slice(0, 15);
    if (ingredients.length < 2 || steps.length === 0) continue;
    if (ingredients.some((i) => banned.some((w) => i.name.toLowerCase().includes(w)))) continue;
    // Spoonacular's price per serving is in US cents; spread it over the grams as a rough per-100 g price. The
    // planner prefers this week's Dutch offers and live prices when it has them.
    const servings = clampInt(source.servings, 1, 12, 2);
    const total = Number(source.pricePerServing) > 0 ? source.pricePerServing! * servings / 100 * USD_TO_EUR : 0;
    const pricePer100g = total > 0 && totalGrams > 0 ? clamp(total / totalGrams * 100, 0.01, 10) : 0.5;
    ingredients.forEach((i) => { i.pricePer100g = Math.round(pricePer100g * 100) / 100; });
    const ready = clampInt(source.readyInMinutes, 0, 600, 30);
    const prep = positive(source.preparationMinutes) ?? Math.round(ready * 0.3);
    const cook = positive(source.cookingMinutes) ?? Math.max(0, ready - prep);
    result.push({
      spoonacularId: source.id,
      name: text(source.title, "Recipe"),
      cuisine: cuisineFor(source, p, course),
      servings,
      prepMinutes: clampInt(prep, 0, 240, 10),
      cookMinutes: clampInt(cook, 0, 480, 20),
      ingredients,
      steps,
      meals: mealsFor(source, course),
      imageURL: https(source.image),
      sourceURL: https(source.sourceUrl) ?? https(source.spoonacularSourceUrl),
      sourceName: source.sourceName ?? null,
      youtubeURL: null,
      youtubeTitle: null,
      youtubeChannel: null,
    });
    if (result.length === COURSES[course].max) break;
  }
  return result;
}

function titleCase(name: string): string {
  return name.trim().replace(/\s+/g, " ").replace(/\b\p{L}/gu, (c) => c.toUpperCase()).slice(0, 60);
}

// ---- YouTube ----

/** A YouTube search for a recipe's video: a few results, so one that fits can be picked. For a vegetarian or vegan
 *  diet the search says so (unless the name does), so "Couscous Biryani" doesn't find a chicken biryani. One search
 *  costs 100 of the 10,000 free daily units however many results it returns. */
export function youtubeQuery(recipeName: string, apiKey: string, diet = ""): URLSearchParams {
  const dietWord = diet === "Vegetarian" || diet === "Vegan" ? diet.toLowerCase() : "";
  const name = dietWord && !new RegExp(`\\b(${dietWord}|vegan)\\b`, "i").test(recipeName)
    ? `${dietWord} ${recipeName}` : recipeName;
  return new URLSearchParams({
    part: "snippet", type: "video", maxResults: "5", relevanceLanguage: "en", safeSearch: "strict",
    q: `${name} recipe`, key: apiKey,
  });
}

const MEAT_IN_TITLE = /\b(chicken|beef|pork|mutton|lamb|fish|prawns?|shrimps?|keema|bacon|ham|turkey|meat|egg)\b/i;
const EGG_FREE_DIETS = ["Vegan"];

/** The best video in a YouTube search response, or null when there is none. Shorts are skipped when there's a full
 *  video, and for a vegetarian or vegan diet so is any video whose title names meat or fish (and, for vegan, egg)
 *  that the recipe's own name doesn't. */
export function youtubeVideo(response: unknown, recipeName = "", diet = ""):
  { url: string; title: string; channel: string } | null {
  type Item = { id?: { videoId?: string }; snippet?: { title?: string; channelTitle?: string } };
  const items = ((response as { items?: Item[] })?.items ?? [])
    .filter((item) => /^[\w-]{11}$/.test(item?.id?.videoId ?? ""))
    .map((item) => ({
      url: `https://www.youtube.com/watch?v=${item.id!.videoId}`,
      title: decodeEntities(item.snippet?.title ?? ""),
      channel: decodeEntities(item.snippet?.channelTitle ?? ""),
    }));
  const meatFree = diet === "Vegetarian" || diet === "Vegan";
  const wrongDish = (title: string) => {
    if (!meatFree) return false;
    const found = title.match(new RegExp(MEAT_IN_TITLE, "gi")) ?? [];
    return found.some((word) => (word.toLowerCase() !== "egg" || EGG_FREE_DIETS.includes(diet))
      && !new RegExp(`\\b${word}\\b`, "i").test(recipeName));
  };
  const fitting = items.filter((v) => !wrongDish(v.title));
  return fitting.find((v) => !/#shorts?\b/i.test(v.title)) ?? fitting[0] ?? null;
}

/** YouTube returns titles with HTML entities ("Mom&#39;s Dal"). */
function decodeEntities(text: string): string {
  return text.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">").slice(0, 150);
}
