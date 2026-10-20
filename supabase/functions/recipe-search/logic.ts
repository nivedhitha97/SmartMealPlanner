// Recipe search: real recipes from Spoonacular, adapted by Claude Haiku to the app's format (grams, nutrition per
// 100 g, Dutch supermarket prices, short steps). Pure functions only, so they can be tested without Deno or the
// network (node --test logic.test.ts); index.ts does the I/O.

export const CLAUDE_MODEL = "claude-haiku-5-5";

/** A week needs breakfasts as well as lunches and dinners; each is a separate Spoonacular search and Claude call. */
export type Course = "breakfast" | "main";
export const COURSES: Record<Course, { type: string; results: number; max: number; meals: string[]; cuisines: boolean }> = {
  // Breakfasts aren't limited to the user's cuisines: few cuisines have many.
  breakfast: { type: "breakfast", results: 10, max: 6, meals: ["Breakfast"], cuisines: false },
  main: { type: "main course", results: 20, max: 12, meals: ["Lunch", "Dinner"], cuisines: true },
};
export const MAX_RECIPES = Math.max(...Object.values(COURSES).map((c) => c.max));

export type Preferences = {
  diet: string;
  cuisines: string[];
  allergies: string[];
  dislikes: string[];
  people: number;
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

export function spoonacularQuery(p: Preferences, apiKey: string, course: Course = "main"): URLSearchParams {
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
  return query;
}

type Nutrient = { name?: string; amount?: number };
type SpoonIngredient = {
  name?: string; nameClean?: string | null; amount?: number; unit?: string;
  measures?: { metric?: { amount?: number; unitShort?: string } };
};
export type SpoonRecipe = {
  id: number; title: string; image?: string; servings?: number; readyInMinutes?: number;
  preparationMinutes?: number | null; cookingMinutes?: number | null; sourceUrl?: string; sourceName?: string;
  spoonacularSourceUrl?: string; cuisines?: string[];
  extendedIngredients?: SpoonIngredient[];
  nutrition?: { ingredients?: { name?: string; amount?: number; unit?: string; nutrients?: Nutrient[] }[] };
  analyzedInstructions?: { steps?: { step?: string }[] }[];
};

/** What Claude needs from each Spoonacular recipe, kept small: fewer tokens, lower cost. */
export function compactRecipes(results: SpoonRecipe[]) {
  return results.map((r) => {
    const nutrition = new Map(
      (r.nutrition?.ingredients ?? []).map((n) => [String(n.name ?? "").toLowerCase(), n]),
    );
    return {
      id: r.id,
      title: r.title,
      cuisines: r.cuisines ?? [],
      servings: r.servings ?? 2,
      readyInMinutes: r.readyInMinutes ?? null,
      preparationMinutes: positive(r.preparationMinutes),
      cookingMinutes: positive(r.cookingMinutes),
      ingredients: (r.extendedIngredients ?? []).slice(0, 15).map((i) => {
        const name = i.nameClean || i.name || "";
        const metric = i.measures?.metric;
        const n = nutrition.get(String(i.name ?? "").toLowerCase()) ?? nutrition.get(name.toLowerCase());
        const value = (key: string) => n?.nutrients?.find((x) => x.name === key)?.amount ?? null;
        return {
          name,
          amount: metric ? `${round(metric.amount ?? 0)} ${metric.unitShort ?? ""}`.trim() : `${i.amount ?? ""} ${i.unit ?? ""}`.trim(),
          nutritionForAmount: n
            ? { calories: value("Calories"), protein: value("Protein"), carbs: value("Carbohydrates"), fat: value("Fat") }
            : null,
        };
      }),
      steps: (r.analyzedInstructions ?? []).flatMap((a) => a.steps ?? []).map((s) => String(s.step ?? "").slice(0, 300))
        .filter(Boolean).slice(0, 15),
    };
  });
}

function positive(value: number | null | undefined): number | null {
  return typeof value === "number" && value > 0 ? value : null;
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

// ---- Claude ----

const INGREDIENT_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string", description: "Plain English ingredient name, singular, Title Case, e.g. Chicken Breast" },
    grams: { type: "integer", description: "Grams for the whole recipe (convert cups, pieces, ml…)" },
    caloriesPer100g: { type: "number" },
    proteinPer100g: { type: "number" },
    carbsPer100g: { type: "number" },
    fatPer100g: { type: "number" },
    pricePer100g: { type: "number", description: "Typical Albert Heijn / Jumbo price in euros per 100 g" },
  },
  required: ["name", "grams", "caloriesPer100g", "proteinPer100g", "carbsPer100g", "fatPer100g", "pricePer100g"],
};

export const RECIPE_TOOL = {
  name: "save_recipes",
  description: "Save the recipes adapted for the user's meal planner.",
  input_schema: {
    type: "object",
    properties: {
      recipes: {
        type: "array",
        maxItems: MAX_RECIPES,
        items: {
          type: "object",
          properties: {
            spoonacularId: { type: "integer", description: "The id of the Spoonacular recipe this is based on" },
            name: { type: "string" },
            cuisine: { type: "string", description: "One of the user's cuisines when it fits, else the recipe's own" },
            servings: { type: "integer" },
            prepMinutes: { type: "integer" },
            cookMinutes: { type: "integer" },
            ingredients: { type: "array", items: INGREDIENT_SCHEMA },
            steps: { type: "array", items: { type: "string" }, description: "6 to 10 detailed method steps with amounts, heat and timings" },
          },
          required: ["spoonacularId", "name", "cuisine", "servings", "prepMinutes", "cookMinutes", "ingredients", "steps"],
        },
      },
    },
    required: ["recipes"],
  },
};

export const systemPrompt = (course: Course) => `You adapt recipes for a meal-planning app used in the Netherlands.
You get recipes found on Spoonacular and the user's preferences. Keep each recipe faithful to its source:
the same dish, ingredients and method. Your job is only to put them in the app's format:
- every ingredient in grams for the whole recipe (convert cups, spoons, pieces and millilitres);
- nutrition per 100 g, using the given nutrition for the amount where present, else typical values;
- a realistic price per 100 g at Dutch supermarkets (Albert Heijn, Jumbo) in euros;
- 6 to 10 detailed method steps: amounts, heat levels, timings and how to tell when it is done.
Leave out any recipe that contains an ingredient the user is allergic to or dislikes, even as a minor
ingredient or in a sauce. Never add ingredients. These are ${course === "breakfast" ? "breakfasts" : "lunch and dinner dishes"}.
Return at most ${COURSES[course].max} recipes with the save_recipes tool.`;

export function claudeRequest(p: Preferences, recipes: ReturnType<typeof compactRecipes>, course: Course = "main") {
  const user = [
    `Preferences: diet ${p.diet}; cooking for ${p.people} ${p.people === 1 ? "person" : "people"}.`,
    p.cuisines.length ? `Cuisines they like: ${p.cuisines.join(", ")}.` : "",
    p.allergies.length ? `Allergies (never include): ${p.allergies.join(", ")}.` : "",
    p.dislikes.length ? `Dislikes (never include): ${p.dislikes.join(", ")}.` : "",
    "",
    "Spoonacular recipes (JSON):",
    JSON.stringify(recipes),
  ].filter((line, i) => line !== "" || i > 3).join("\n");
  return {
    model: CLAUDE_MODEL,
    max_tokens: 16000,
    system: systemPrompt(course),
    tools: [RECIPE_TOOL],
    tool_choice: { type: "tool", name: RECIPE_TOOL.name },
    messages: [{ role: "user", content: user }],
  };
}

type ClaudeResponse = { content?: { type: string; name?: string; input?: { recipes?: unknown[] } }[] };

/** Claude's recipes, checked and joined with Spoonacular's photo and source link (never taken from the model). */
export function adaptedRecipes(
  response: ClaudeResponse, sources: SpoonRecipe[], p: Preferences, course: Course = "main",
): AppRecipe[] {
  const block = response.content?.find((c) => c.type === "tool_use" && c.name === RECIPE_TOOL.name);
  const byId = new Map(sources.map((s) => [s.id, s]));
  const banned = [...p.allergies, ...p.dislikes].map((w) => w.toLowerCase()).filter((w) => w.length > 2);
  const result: AppRecipe[] = [];
  for (const raw of block?.input?.recipes ?? []) {
    const r = raw as Record<string, unknown>;
    const source = byId.get(Number(r.spoonacularId));
    if (!source) continue; // only recipes that really came from Spoonacular
    const ingredients = (Array.isArray(r.ingredients) ? r.ingredients : []).map(ingredient).filter(
      (i): i is AppIngredient => i !== null,
    );
    const steps = (Array.isArray(r.steps) ? r.steps : []).filter((s): s is string => typeof s === "string" && s.trim() !== "")
      .map((s) => s.trim().slice(0, 500)).slice(0, 10);
    if (ingredients.length < 2 || steps.length === 0) continue;
    if (ingredients.some((i) => banned.some((w) => i.name.toLowerCase().includes(w)))) continue;
    result.push({
      spoonacularId: source.id,
      name: text(r.name, source.title),
      cuisine: cuisineFor(r.cuisine, source, p, course),
      servings: clampInt(r.servings, 1, 12, source.servings ?? 2),
      prepMinutes: clampInt(r.prepMinutes, 0, 240, 10),
      cookMinutes: clampInt(r.cookMinutes, 0, 480, 20),
      ingredients,
      steps,
      meals: COURSES[course].meals,
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

/** The cuisine in the user's own words ("Dutch", not Spoonacular's "European"), so the app keeps lunches and dinners
 *  to the cuisines they chose. The search was filtered by those cuisines, so every main belongs to one of them. */
function cuisineFor(raw: unknown, source: SpoonRecipe, p: Preferences, course: Course): string {
  const fallback = text(raw, source.cuisines?.[0] ?? "International");
  if (course === "breakfast" || !p.cuisines.length) return fallback;
  const said = fallback.toLowerCase();
  const sourceCuisines = (source.cuisines ?? []).map((c) => c.toLowerCase());
  return p.cuisines.find((c) => c.toLowerCase() === said)
    ?? p.cuisines.find((c) => sourceCuisines.includes((CUISINES[c.toLowerCase()] ?? c).toLowerCase()))
    ?? p.cuisines[0];
}

function ingredient(raw: unknown): AppIngredient | null {
  if (typeof raw !== "object" || raw === null) return null;
  const i = raw as Record<string, unknown>;
  const name = text(i.name, "");
  const grams = clampInt(i.grams, 1, 5000, 0);
  if (!name || grams === 0) return null;
  return {
    name,
    grams,
    caloriesPer100g: clamp(i.caloriesPer100g, 0, 900),
    proteinPer100g: clamp(i.proteinPer100g, 0, 100),
    carbsPer100g: clamp(i.carbsPer100g, 0, 100),
    fatPer100g: clamp(i.fatPer100g, 0, 100),
    pricePer100g: clamp(i.pricePer100g, 0.01, 10),
  };
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

// ---- YouTube ----

/** The YouTube Data API search for a recipe's video: one video, the most relevant. Costs 100 of 10,000 daily units. */
export function youtubeQuery(recipeName: string, apiKey: string): URLSearchParams {
  return new URLSearchParams({
    part: "snippet", type: "video", maxResults: "1", relevanceLanguage: "en", safeSearch: "strict",
    q: `${recipeName} recipe`, key: apiKey,
  });
}

/** The video in a YouTube search response, or null when there is none. */
export function youtubeVideo(response: unknown): { url: string; title: string; channel: string } | null {
  const item = (response as { items?: { id?: { videoId?: string }; snippet?: { title?: string; channelTitle?: string } }[] })
    ?.items?.[0];
  const id = item?.id?.videoId;
  if (!id || !/^[\w-]{11}$/.test(id)) return null;
  return {
    url: `https://www.youtube.com/watch?v=${id}`,
    title: decodeEntities(item?.snippet?.title ?? ""),
    channel: decodeEntities(item?.snippet?.channelTitle ?? ""),
  };
}

/** YouTube returns titles with HTML entities ("Mom&#39;s Dal"). */
function decodeEntities(text: string): string {
  return text.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">").slice(0, 150);
}
