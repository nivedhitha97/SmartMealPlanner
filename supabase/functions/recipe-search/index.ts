// Supabase Edge Function: POST the user's preferences, get up to 6 recipes from Spoonacular adapted by Claude Haiku.
//
// Secrets (supabase secrets set …): SPOONACULAR_API_KEY, ANTHROPIC_API_KEY, RECIPE_SEARCH_APP_KEY (the key the
// app sends in the x-app-key header; it ships inside the app, so it only keeps out casual callers).
// Optional: YOUTUBE_API_KEY (a real video for each recipe; without it the app links a YouTube search) and
// RECIPE_SEARCH_DAILY_LIMIT (default 40 new searches a day, all users together).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase and used for the cache and the daily limit
// (tables in supabase/recipe_search_schema.sql).
//
// Deploy: supabase functions deploy recipe-search --no-verify-jwt

import {
  adaptedRecipes,
  type AppRecipe,
  cacheKeySource,
  claudeRequest,
  compactRecipes,
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

  // New searches cost Spoonacular points and Claude tokens: cap them per caller and in total.
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
    await addVideos(recipes);

    if (!failed.length) { // a partial result isn't cached, so the next search tries again
      await database("recipe_search_cache", {
        method: "POST",
        body: { key, recipes, created_at: new Date().toISOString() },
        prefer: "resolution=merge-duplicates",
      });
    }
    return json({ recipes, complete: failed.length === 0 });
  } catch (error) {
    console.error(error);
    return json({ error: "Recipe search failed" }, 502);
  }
});

/** Spoonacular's recipes for one course, adapted by Claude Haiku ([] when there are none); throws when a service fails. */
async function findRecipes(preferences: Preferences, course: Course): Promise<AppRecipe[]> {
  const search = await fetch(
    "https://api.spoonacular.com/recipes/complexSearch?" + spoonacularQuery(preferences, env("SPOONACULAR_API_KEY"), course),
  );
  if (!search.ok) throw new Error(`Spoonacular (${course}): HTTP ${search.status}`);
  const results: SpoonRecipe[] = (await search.json()).results ?? [];
  if (!results.length) return [];

  const claude = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env("ANTHROPIC_API_KEY"),
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify(claudeRequest(preferences, compactRecipes(results), course)),
  });
  if (!claude.ok) throw new Error(`Claude (${course}): HTTP ${claude.status}`);
  return adaptedRecipes(await claude.json(), results, preferences, course);
}

/** A real YouTube video for each recipe, when a YouTube key is set. A failed lookup (e.g. the daily quota) leaves the
 *  recipe without one, and the app links a YouTube search instead. */
async function addVideos(recipes: AppRecipe[]) {
  const apiKey = env("YOUTUBE_API_KEY");
  if (!apiKey) return;
  await Promise.all(recipes.map(async (recipe) => {
    try {
      const response = await fetch("https://www.googleapis.com/youtube/v3/search?" + youtubeQuery(recipe.name, apiKey));
      if (!response.ok) return;
      const video = youtubeVideo(await response.json());
      if (video) Object.assign(recipe, { youtubeURL: video.url, youtubeTitle: video.title, youtubeChannel: video.channel });
    } catch {
      // keep the search fallback
    }
  }));
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
