//
//  RecipeDiscovery.swift
//  SmartMealPlanner
//
//  The recipes the planner uses: genuine, human-made recipes found on Spoonacular (published on real recipe sites)
//  through the recipe-search function (RecipeSearchService), never written or rewritten by AI. AI only helps find
//  them: where Apple Intelligence is on, the on-device model (Foundation Models) suggests dish names that fit the
//  preferences, and the search looks those dishes up. Every recipe is checked against the diet, allergies and dislikes
//  before it can be planned, and the last results are kept for offline use.
//

import CryptoKit
import Foundation
import FoundationModels

// MARK: - Dish ideas (AI picks what to search for, never the recipe)

@Generable(description: "Dishes to search for in a recipe collection")
struct DishIdeas {
    @Guide(description: "Names of well-known, home-cooked dishes, e.g. Chana Masala, Shakshuka, Pasta e Fagioli", .count(8))
    var dishes: [String]
}

/// Suggests dish names that fit the preferences; empty when it can't (the search then filters by preferences alone).
protocol DishIdeaSuggesting {
    func ideas(for preferences: UserPreferences) async -> [String]
}

/// Apple's on-device model (Apple Intelligence: iPhone 15 Pro and later, iOS 26): free, and the preferences stay on
/// the phone until the search.
struct OnDeviceDishIdeas: DishIdeaSuggesting {
    func ideas(for preferences: UserPreferences) async -> [String] {
        guard case .available = SystemLanguageModel.default.availability else { return [] }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let answer = try await session.respond(to: Self.prompt(for: preferences), generating: DishIdeas.self)
            return Self.cleaned(answer.content.dishes)
        } catch {
            return []
        }
    }

    static let instructions = """
        You help find recipes in a recipe collection. Suggest the names of real, well-known home-cooked dishes that \
        fit the person's diet and cuisines. Only dish names: no recipes, no descriptions. Never suggest a dish that \
        usually contains something they are allergic to or dislike.
        """

    static func prompt(for preferences: UserPreferences) -> String {
        var lines = ["Suggest 8 different dishes for lunch and dinner, for \(preferences.people) "
                     + (preferences.people == 1 ? "person." : "people.")]
        lines.append("Diet: \(preferences.dietType).")
        if !preferences.cuisines.isEmpty {
            lines.append("Cuisines: \(preferences.cuisines.joined(separator: ", ")).")
        }
        if !preferences.allergies.isEmpty {
            lines.append("Allergies (never): \(preferences.allergies.joined(separator: ", ")).")
        }
        if !preferences.dislikes.isEmpty {
            lines.append("Dislikes (avoid): \(preferences.dislikes.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    /// Short, distinct names only.
    static func cleaned(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 40 && seen.insert($0.lowercased()).inserted }
            .prefix(8).map { $0 }
    }
}

/// No ideas: the search filters by the preferences alone (UI tests, and devices without Apple Intelligence).
struct NoDishIdeas: DishIdeaSuggesting {
    func ideas(for preferences: UserPreferences) async -> [String] { [] }
}

// MARK: - Discovery

/// The recipes found, or a note saying why there are none.
struct DiscoveredRecipes: Equatable {
    var recipes: [Recipe]
    var note: String?

    static func == (lhs: DiscoveredRecipes, rhs: DiscoveredRecipes) -> Bool {
        lhs.recipes.map(\.id) == rhs.recipes.map(\.id) && lhs.note == rhs.note
    }
}

@MainActor
final class RecipeDiscovery {
    /// UI tests (`-uiTestingBundledData`, `-uiTestingFixtureRecipes`) get their fixed recipes; everyone else searches.
    static let shared = LaunchArguments.contains(LaunchArguments.bundledData)
        || LaunchArguments.contains(LaunchArguments.fixtureRecipes)
        ? RecipeDiscovery(search: FixtureRecipeSearch(), ideas: NoDishIdeas(),
                          cacheURL: URL.temporaryDirectory.appending(path: "ui-test-recipes.json"))
        : RecipeDiscovery()

    /// Searched recipes are kept this long before a new search (the function's cache lasts as long).
    static let freshDays = 7

    static let offlineNote = "No internet connection. Connect to find recipes for your preferences."
    static let notSetUpNote = "Recipe search isn't set up yet, so there are no recipes to plan with."
    static let plannerNote = "Recipes from Spoonacular, as their authors published them; each links to the original."

    /// Where recipes are kept. Recipes saved by earlier versions (`ai-recipes.json`) may have been written by AI, so
    /// they are never used: the file is removed.
    nonisolated static let defaultCacheURL = URL.applicationSupportDirectory.appending(path: "searched-recipes.json")
    private static let oldAIRecipesURL = URL.applicationSupportDirectory.appending(path: "ai-recipes.json")

    private let search: RecipeSearching
    private let ideas: DishIdeaSuggesting
    private let cacheURL: URL
    private let now: () -> Date

    init(search: RecipeSearching = RemoteRecipeSearch(),
         ideas: DishIdeaSuggesting = OnDeviceDishIdeas(),
         cacheURL: URL = RecipeDiscovery.defaultCacheURL,
         now: @escaping () -> Date = Date.init) {
        self.search = search
        self.ideas = ideas
        self.cacheURL = cacheURL
        self.now = now
        if cacheURL == Self.defaultCacheURL {
            try? FileManager.default.removeItem(at: Self.oldAIRecipesURL)
        }
    }

    var isAvailable: Bool { search.isConfigured }

    /// Recipes for these preferences, the only recipes the planner uses:
    /// 1. the saved ones, while the preferences are unchanged and they are less than a week old;
    /// 2. a new search (with the on-device model's dish ideas, where it has some);
    /// 3. when that can't be reached, the saved ones however old (offline, the app shows what it stored);
    /// 4. else none, with a note saying why.
    /// Recipes that break the diet, allergies or dislikes are always dropped.
    func recipes(for preferences: UserPreferences, forceNew: Bool = false) async -> DiscoveredRecipes {
        let key = Self.cacheKey(for: preferences)
        let saved = loadCache().flatMap { $0.key == key ? $0 : nil }
        if !forceNew, let saved, now().timeIntervalSince(saved.savedAt) < Double(Self.freshDays) * 86_400 {
            return DiscoveredRecipes(recipes: saved.recipes, note: nil)
        }
        guard search.isConfigured else {
            return DiscoveredRecipes(recipes: saved?.recipes ?? [], note: saved == nil ? Self.notSetUpNote : nil)
        }
        do {
            let dishIdeas = await ideas.ideas(for: preferences)
            let safe = Self.safe(try await search.search(for: preferences, ideas: dishIdeas), for: preferences)
            saveCache(Cache(key: key, recipes: safe, savedAt: now()))
            return DiscoveredRecipes(recipes: safe, note: safe.isEmpty ? "No recipe matched all your preferences." : nil)
        } catch {
            if let saved, !saved.recipes.isEmpty {
                return DiscoveredRecipes(recipes: saved.recipes, note: nil)
            }
            return DiscoveredRecipes(recipes: [], note: Self.isOffline(error)
                ? Self.offlineNote : "Couldn't reach recipe search; try again later.")
        }
    }

    /// The recipes saved by the last search, whatever the preferences (e.g. for picking ingredient names).
    func savedRecipes() -> [Recipe] {
        loadCache()?.recipes ?? []
    }

    /// Diet, allergies and dislikes only: the search already chose the cuisines, and breakfasts may come from any
    /// cuisine (the planner keeps lunches and dinners to the chosen ones).
    private static func safe(_ recipes: [Recipe], for preferences: UserPreferences) -> [Recipe] {
        var anyCuisine = preferences
        anyCuisine.cuisines = []
        return MealPlanner().filterRecipes(recipes, anyCuisine)
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                .timedOut, .dataNotAllowed, .internationalRoamingOff].contains(code)
    }

    /// Recipes depend on these preferences; anything else (budget, postcode) doesn't need new recipes.
    static func cacheKey(for preferences: UserPreferences) -> String {
        let parts = [preferences.dietType, preferences.cuisines.sorted().joined(separator: ","),
                     preferences.allergies.map { $0.lowercased() }.sorted().joined(separator: ","),
                     preferences.dislikes.map { $0.lowercased() }.sorted().joined(separator: ",")]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let key: String
        let recipes: [Recipe]
        let savedAt: Date
    }

    private func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func saveCache(_ cache: Cache) {
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }
}

/// For UI tests: the fixed recipes in Data/UITestRecipes.json, as if a search had found them.
struct FixtureRecipeSearch: RecipeSearching {
    var isConfigured: Bool { true }
    func search(for preferences: UserPreferences, ideas: [String]) async throws -> [Recipe] {
        try JSONLoader.load("UITestRecipes", as: [Recipe].self)
    }
}
