//
//  RecipeDiscovery.swift
//  SmartMealPlanner
//
//  The recipes the planner uses: human-written recipes from the Wikibooks Cookbook (RecipeLibrary), never written or
//  rewritten by AI. AI only helps choose: where Apple Intelligence is on, the on-device model (Foundation Models)
//  suggests dish names that fit the preferences, and recipes with those names are preferred. Every recipe is checked
//  against the diet, allergies and dislikes on the phone, so preferences never leave it.
//

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
    /// UI tests (`-uiTestingBundledData`) get their fixed recipes; everyone else the Wikibooks recipes.
    static let shared = LaunchArguments.contains(LaunchArguments.bundledData)
        ? RecipeDiscovery(library: FixtureRecipeLibrary(), ideas: NoDishIdeas())
        : RecipeDiscovery()

    /// How many recipes the planner gets per kind: enough for variety, the dish ideas first.
    static let maxMains = 40
    static let maxBreakfasts = 20

    static let offlineNote = "No internet connection. Connect once to download the recipes; after that they work offline."
    static let unreachableNote = "Couldn't download the recipes; try again later."
    static let noMatchNote = "No recipe matched all your preferences."
    static let plannerNote = "Recipes from the Wikibooks Cookbook, written by its contributors (CC BY-SA 4.0); each "
        + "recipe credits its authors and links to its source."

    private let library: RecipeLibrary
    private let ideas: DishIdeaSuggesting

    init(library: RecipeLibrary = RemoteRecipeLibrary(), ideas: DishIdeaSuggesting = OnDeviceDishIdeas()) {
        self.library = library
        self.ideas = ideas
    }

    /// Recipes for these preferences: those that fit the diet, allergies and dislikes, breakfasts from any cuisine and
    /// lunches and dinners from the chosen cuisines (the planner keeps to them), dishes the on-device model suggests
    /// first. With no recipes on the phone and no connection, none, with a note saying why.
    func recipes(for preferences: UserPreferences) async -> DiscoveredRecipes {
        let all: [Recipe]
        do {
            all = try await library.recipes()
        } catch {
            return DiscoveredRecipes(recipes: [], note: Self.isOffline(error) ? Self.offlineNote : Self.unreachableNote)
        }
        let safe = Self.safe(all, for: preferences)
        let breakfasts = safe.filter { $0.meals?.contains(MealSlot.breakfast.rawValue) == true }
        let mains = safe.filter { recipe in
            recipe.meals?.contains(MealSlot.breakfast.rawValue) != true
                && (preferences.cuisines.isEmpty || preferences.cuisines.contains(recipe.cuisine))
        }
        let dishIdeas = mains.count > Self.maxMains ? await ideas.ideas(for: preferences) : []
        let chosen = Array(Self.ranked(mains, ideas: dishIdeas).prefix(Self.maxMains))
            + Array(breakfasts.shuffled().prefix(Self.maxBreakfasts))
        return DiscoveredRecipes(recipes: chosen, note: chosen.isEmpty ? Self.noMatchNote : nil)
    }

    /// The recipes kept on this phone, whatever the preferences (e.g. for picking ingredient names).
    func savedRecipes() -> [Recipe] {
        library.savedRecipes()
    }

    /// Recipes whose name contains one of the dish ideas first, the rest in random order (a new mix each week).
    static func ranked(_ recipes: [Recipe], ideas: [String]) -> [Recipe] {
        let wanted = ideas.map { $0.lowercased() }
        let (matching, others) = recipes.shuffled().reduce(into: ([Recipe](), [Recipe]())) { result, recipe in
            let name = recipe.name.lowercased()
            if wanted.contains(where: { name.contains($0) || $0.contains(name) }) {
                result.0.append(recipe)
            } else {
                result.1.append(recipe)
            }
        }
        return matching + others
    }

    /// Diet, allergies and dislikes only: the planner decides which cuisines a meal may come from.
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
}
