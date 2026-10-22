// Supabase Edge Function: POST the user's preferences (and, optionally, dish ideas from the app's on-device AI), get
// up to 6 breakfasts and 12 lunch/dinner dishes: genuine recipes from Spoonacular, never written or changed by AI.
//
// Secrets (supabase secrets set …): SPOONACULAR_API_KEY and RECIPE_SEARCH_APP_KEY (the key the app sends in the
// x-app-key header; it ships inside the app, so it only keeps out casual callers). Optional:
//   YOUTUBE_API_KEY            a real video for each recipe (free quota); without it the app links a YouTube search.
//   RECIPE_SEARCH_DAILY_LIMIT  default 40 new searches a day, all users together.
// Everything used is free: Supabase's free plan, Spoonacular's free plan and the YouTube Data API's free quota.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase and used for the cache and the daily limit
// (tables in supabase/recipe_search_schema.sql).
//
// Deploy: supabase functions deploy recipe-search --no-verify-jwt

import {
  convertedRecipes,
  type AppRecipe,
  cacheKeySource,
  COURSES,
  type Course,
  parsePreferences,
  type Preferences,
  spoonacularQuery,
  type SpoonRecipe,
  youtubeQuery,
  youtubeVideo,
} from "./logic.ts";

const env = (name: string) => Deno.env.get(name) ?? "";
const CACHE_DAYS = 7;
const PER_CALLER_DAILY_LIMIT = 10;

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Use POST" }, 405);
  if (!env("RECIPE_SEARCH_APP_KEY") || request.headers.get("x-app-key") !== env("RECIPE_SEARCH_APP_KEY")) {
    return json({ error: "Unknown app" }, 401);
  }
  let preferences;
  try {
    preferences = parsePreferences(await request.json());
  } catch (error) {
    return json({ error: String((error as Error).message ?? error) }, 400);
  }

  const key = await sha256(cacheKeySource(preferences));
  const cached = await database(`recipe_search_cache?key=eq.${key}&created_at=gte.${daysAgo(CACHE_DAYS)}&select=recipes`);
  if (Array.isArray(cached) && cached.length) return json({ recipes: cached[0].recipes, cached: true });

  // New searches cost Spoonacular points: cap them per caller and in total.
  const caller = await sha256(request.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown");
  const today = daysAgo(1);
  const [mine, all] = await Promise.all([
    count(`recipe_search_log?caller=eq.${caller}&created_at=gte.${today}`),
    count(`recipe_search_log?created_at=gte.${today}`),
  ]);
  const dailyLimit = Number(env("RECIPE_SEARCH_DAILY_LIMIT") || 40);
  if (mine >= PER_CALLER_DAILY_LIMIT || all >= dailyLimit) {
    return json({ error: "Daily recipe search limit reached; try again tomorrow" }, 429);
  }
  await database("recipe_search_log", { method: "POST", body: { caller } });

  try {
    // Breakfasts and mains are searched and adapted side by side; one failing doesn't lose the other.
    const courses = await Promise.allSettled(
      (["breakfast", "main"] as Course[]).map((course) => findRecipes(preferences, course)),
    );
    const failed = courses.filter((c) => c.status === "rejected") as PromiseRejectedResult[];
    failed.forEach((c) => console.error(c.reason));
    if (failed.length === courses.length) return json({ error: "Recipe search failed" }, 502);
    const recipes = courses.flatMap((c) => (c.status === "fulfilled" ? c.value : []));
    const videoError = await addVideos(recipes, preferences.diet);

    // A partial result, or one whose video lookups all failed, isn't cached, so the next search tries again.
    if (!failed.length && !videoError) {
      await database("recipe_search_cache", {
        method: "POST",
        body: { key, recipes, created_at: new Date().toISOString() },
        prefer: "resolution=merge-duplicates",
      });
    }
    return json({ recipes, complete: failed.length === 0, ...(videoError ? { videoError } : {}) });
  } catch (error) {
    console.error(error);
    return json({ error: "Recipe search failed" }, 502);
  }
});

/** Genuine recipes for one course, in the app's format ([] when there are none); throws when Spoonacular fails.
 *  Breakfasts come from one search. Lunches and dinners come from the dish ideas first (each searched by name, so the
 *  AI only chooses what to look for), topped up with a plain search for the preferences when they bring too few. */
async function findRecipes(preferences: Preferences, course: Course): Promise<AppRecipe[]> {
  const sources: SpoonRecipe[] = [];
  const add = (results: SpoonRecipe[]) => {
    for (const r of results) if (!sources.some((s) => s.id === r.id)) sources.push(r);
  };
  if (course === "main" && preferences.ideas.length) {
    const found = await Promise.allSettled(preferences.ideas.map((idea) => search(preferences, course, idea)));
    found.forEach((f) => { if (f.status === "fulfilled") add(f.value); });
  }
  let recipes = convertedRecipes(sources, preferences, course);
  if (recipes.length < COURSES[course].max) {
    add(await search(preferences, course));
    recipes = convertedRecipes(sources, preferences, course);
  }
  return recipes;
}

async function search(preferences: Preferences, course: Course, idea?: string): Promise<SpoonRecipe[]> {
  const response = await fetch(
    "https://api.spoonacular.com/recipes/complexSearch?" +
      spoonacularQuery(preferences, env("SPOONACULAR_API_KEY"), course, idea),
  );
  if (!response.ok) throw new Error(`Spoonacular (${idea ?? course}): HTTP ${response.status}`);
  return (await response.json()).results ?? [];
}

/** A real YouTube video for each recipe, when a YouTube key is set. A failed lookup (e.g. the daily quota) leaves the
 *  recipe without one, and the app links a YouTube search instead. Returns YouTube's reason when every lookup failed
 *  (e.g. the API not enabled for the key), so it can be fixed. */
async function addVideos(recipes: AppRecipe[], diet: string): Promise<string | undefined> {
  const apiKey = env("YOUTUBE_API_KEY");
  if (!apiKey || !recipes.length) return;
  const errors = await Promise.all(recipes.map(async (recipe): Promise<string | undefined> => {
    try {
      const response = await fetch("https://www.googleapis.com/youtube/v3/search?" + youtubeQuery(recipe.name, apiKey, diet));
      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        return `YouTube: HTTP ${response.status} ${body?.error?.errors?.[0]?.reason ?? body?.error?.message ?? ""}`.trim();
      }
      const video = youtubeVideo(await response.json(), recipe.name, diet);
      if (video) Object.assign(recipe, { youtubeURL: video.url, youtubeTitle: video.title, youtubeChannel: video.channel });
    } catch (error) {
      return `YouTube: ${(error as Error).message ?? error}`;
    }
  }));
  if (errors.every(Boolean)) {
    console.error(errors[0]);
    return errors[0];
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function daysAgo(days: number): string {
  return new Date(Date.now() - days * 86_400_000).toISOString();
}

/** PostgREST with the service role key (server side only); returns parsed JSON, or null on any problem. */
async function database(path: string, options: { method?: string; body?: unknown; prefer?: string } = {}) {
  try {
    const response = await fetch(`${env("SUPABASE_URL")}/rest/v1/${path}`, {
      method: options.method ?? "GET",
      headers: {
        apikey: env("SUPABASE_SERVICE_ROLE_KEY"),
        authorization: `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`,
        "content-type": "application/json",
        ...(options.prefer ? { prefer: options.prefer } : {}),
      },
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
    if (!response.ok) return null;
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

/** Rows matching `path`; Infinity when the log can't be read, so the limit fails closed. */
async function count(path: string): Promise<number> {
  const rows = await database(`${path}&select=caller`);
  return Array.isArray(rows) ? rows.length : Infinity;
}
