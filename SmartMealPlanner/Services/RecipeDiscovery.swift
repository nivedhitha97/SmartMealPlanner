//
//  RecipeDiscovery.swift
//  SmartMealPlanner
//
//  AI-assisted recipe search. When the recipe-search function is set up (RecipeSearchService), real recipes come
//  from Spoonacular, adapted by Claude Haiku. Otherwise, or when that fails, Apple's on-device language model
//  (Foundation Models) writes recipes: free, no API key, and preferences never leave the phone. Every recipe is
//  checked against the same diet, allergy and dislike rules as the bundled ones before it can be planned.
//

import CryptoKit
import Foundation
import FoundationModels

// MARK: - What the model fills in

@Generable(description: "An ingredient of a home-cooked recipe")
struct GeneratedIngredient {
    @Guide(description: "Ingredient name in English, singular and plain, e.g. Chicken Breast, Red Lentils, Spinach")
    var name: String
    @Guide(description: "Grams of this ingredient for the whole recipe", .range(1...2000))
    var grams: Int
    @Guide(description: "Calories per 100 grams", .range(0...900))
    var caloriesPer100g: Int
    @Guide(description: "Protein grams per 100 grams", .range(0...100))
    var proteinPer100g: Double
    @Guide(description: "Carbohydrate grams per 100 grams", .range(0...100))
    var carbsPer100g: Double
    @Guide(description: "Fat grams per 100 grams", .range(0...100))
    var fatPer100g: Double
    @Guide(description: "Typical Dutch supermarket price in euros per 100 grams", .range(0.01...10.0))
    var pricePer100g: Double
}

@Generable(description: "A home-cooked recipe")
struct GeneratedRecipe {
    @Guide(description: "Short dish name, e.g. Spinach and Chickpea Curry")
    var name: String
    var cuisine: String
    @Guide(description: "How many people the ingredient amounts are for", .range(1...6))
    var servings: Int
    @Guide(description: "Hands-on preparation minutes", .range(0...120))
    var prepMinutes: Int
    @Guide(description: "Cooking minutes, 0 for no-cook dishes", .range(0...240))
    var cookMinutes: Int
    @Guide(description: "Every ingredient with its grams", .count(2...12))
    var ingredients: [GeneratedIngredient]
    @Guide(description: "Detailed method steps, one instruction each, with amounts, heat levels and timings", .count(6...10))
    var steps: [String]
}

@Generable(description: "Several different recipes")
struct GeneratedRecipeBatch {
    @Guide(description: "Different dishes; no two alike", .count(6))
    var recipes: [GeneratedRecipe]
}

// MARK: - Discovery

/// Whether AI recipes can be made on this device, and why not.
enum RecipeDiscoveryAvailability: Equatable {
    case available
    case unavailable(String)
}

protocol RecipeGenerating {
    var availability: RecipeDiscoveryAvailability { get }
    func generate(prompt: String, instructions: String) async throws -> [GeneratedRecipe]
}

/// Apple's on-device model (Apple Intelligence: iPhone 15 Pro and later, iOS 26).
struct OnDeviceRecipeGenerator: RecipeGenerating {
    var availability: RecipeDiscoveryAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This iPhone doesn't support Apple Intelligence, so only the built-in recipes are used.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in iOS Settings to discover new recipes.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still getting ready; try again later.")
        case .unavailable:
            return .unavailable("On-device AI isn't available right now.")
        }
    }

    func generate(prompt: String, instructions: String) async throws -> [GeneratedRecipe] {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt, generating: GeneratedRecipeBatch.self).content.recipes
    }
}

/// Where discovered recipes came from.
enum DiscoverySource: String, Codable {
    /// Spoonacular recipes adapted by Claude Haiku (the recipe-search function).
    case spoonacular
    /// Written by Apple's on-device model.
    case onDevice

    /// For the planner notes, e.g. "Includes 4 recipes from Spoonacular, adapted by AI".
    var description: String {
        switch self {
        case .spoonacular: return "from Spoonacular, adapted by AI"
        case .onDevice: return "discovered by on-device AI"
        }
    }
}

/// The result of asking for AI recipes.
struct DiscoveredRecipes: Equatable {
    var recipes: [Recipe]
    /// For the planner notes, e.g. why there are none.
    var note: String?
    var source: DiscoverySource = .onDevice

    static func == (lhs: DiscoveredRecipes, rhs: DiscoveredRecipes) -> Bool {
        lhs.recipes.map(\.id) == rhs.recipes.map(\.id) && lhs.note == rhs.note && lhs.source == rhs.source
    }
}

@MainActor
final class RecipeDiscovery {
    static let shared = RecipeDiscovery()

    private let search: RecipeSearching
    private let generator: RecipeGenerating
    private let cacheURL: URL

    init(search: RecipeSearching = RemoteRecipeSearch(),
         generator: RecipeGenerating = OnDeviceRecipeGenerator(),
         cacheURL: URL = URL.applicationSupportDirectory.appending(path: "ai-recipes.json")) {
        self.search = search
        self.generator = generator
        self.cacheURL = cacheURL
    }

    /// The source tried first: the recipe search when it is set up, else the on-device model.
    var preferredSource: DiscoverySource { search.isConfigured ? .spoonacular : .onDevice }

    var availability: RecipeDiscoveryAvailability { search.isConfigured ? .available : generator.availability }

    /// AI recipes for these preferences: from the cache when the preferences haven't changed, else found anew.
    /// Recipe search comes first; the on-device model is the fallback. Recipes that break the diet, allergies or
    /// dislikes are dropped.
    func recipes(for preferences: UserPreferences, forceNew: Bool = false) async -> DiscoveredRecipes {
        let key = Self.cacheKey(for: preferences)
        if !forceNew, let cached = loadCache(), cached.key == key, cached.source ?? .onDevice == preferredSource {
            return DiscoveredRecipes(recipes: cached.recipes, note: nil, source: cached.source ?? .onDevice)
        }
        var searchFailed = false
        if search.isConfigured {
            do {
                let safe = MealPlanner().filterRecipes(try await search.search(for: preferences), preferences)
                saveCache(Cache(key: key, recipes: safe, source: .spoonacular))
                return DiscoveredRecipes(recipes: safe, note: safe.isEmpty ? "No Spoonacular recipe matched all your preferences." : nil,
                                         source: .spoonacular)
            } catch {
                searchFailed = true  // fall back to the on-device model
            }
        }
        guard case .available = generator.availability else {
            if searchFailed {
                return DiscoveredRecipes(recipes: [], note: "Couldn't reach recipe search this time; the built-in recipes are used.")
            }
            if case .unavailable(let reason) = generator.availability { return DiscoveredRecipes(recipes: [], note: reason) }
            return DiscoveredRecipes(recipes: [], note: nil)
        }
        do {
            let generated = try await generator.generate(prompt: Self.prompt(for: preferences),
                                                         instructions: Self.instructions)
            let safe = MealPlanner().filterRecipes(generated.map(Self.recipe(from:)), preferences)
            saveCache(Cache(key: key, recipes: safe, source: .onDevice))
            return DiscoveredRecipes(recipes: safe, note: safe.isEmpty ? "No AI recipe matched all your preferences." : nil)
        } catch {
            return DiscoveredRecipes(recipes: [], note: "Couldn't create AI recipes this time; the built-in recipes are used.")
        }
    }

    // MARK: - Prompt

    static let instructions = """
        You are a home-cooking assistant in the Netherlands. Write practical recipes with ingredients that are easy \
        to buy at Dutch supermarkets. Give realistic gram amounts, nutrition values and prices. Never include an \
        ingredient the user is allergic to or dislikes, and respect their diet strictly.
        """

    static func prompt(for preferences: UserPreferences) -> String {
        var lines = ["Suggest 6 different dinner or lunch recipes for \(preferences.people) "
                     + (preferences.people == 1 ? "person." : "people.")]
        lines.append("Diet: \(preferences.dietType).")
        if !preferences.cuisines.isEmpty {
            lines.append("Cuisines to choose from: \(preferences.cuisines.joined(separator: ", ")). "
                         + "Set each recipe's cuisine to one of these exactly.")
        }
        if !preferences.allergies.isEmpty {
            lines.append("Allergies (never use): \(preferences.allergies.joined(separator: ", ")).")
        }
        if !preferences.dislikes.isEmpty {
            lines.append("Dislikes (avoid): \(preferences.dislikes.joined(separator: ", ")).")
        }
        lines.append("Keep the total for a week of meals within about €\(Int(preferences.budgetWeekly)).")
        return lines.joined(separator: "\n")
    }

    /// Recipes depend on these preferences; anything else (budget, postcode) doesn't need new recipes.
    static func cacheKey(for preferences: UserPreferences) -> String {
        let parts = [preferences.dietType, preferences.cuisines.sorted().joined(separator: ","),
                     preferences.allergies.map { $0.lowercased() }.sorted().joined(separator: ","),
                     preferences.dislikes.map { $0.lowercased() }.sorted().joined(separator: ",")]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Conversion

    static func recipe(from generated: GeneratedRecipe) -> Recipe {
        let ingredients = generated.ingredients.map { item in
            RecipeIngredient(
                ingredient: Ingredient(name: item.name.trimmingCharacters(in: .whitespaces),
                                       calories: Double(item.caloriesPer100g), protein: item.proteinPer100g,
                                       carbs: item.carbsPer100g, fat: item.fatPer100g,
                                       defaultPrice: item.pricePer100g),
                quantity: Double(item.grams))
        }
        let search = "https://www.youtube.com/results?search_query="
            + (generated.name + " recipe").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).orEmpty
        return Recipe(
            id: UUID(uuidString: deterministicID(generated.name)) ?? UUID(),
            name: generated.name.trimmingCharacters(in: .whitespaces),
            cuisine: generated.cuisine,
            ingredients: ingredients,
            servings: generated.servings,
            prepMinutes: generated.prepMinutes,
            cookMinutes: generated.cookMinutes,
            instructions: generated.steps,
            youtubeURL: search,
            isAIGenerated: true,
            meals: [MealSlot.lunch.rawValue, MealSlot.dinner.rawValue]  // the prompt asks for lunches and dinners
        )
    }

    /// The same dish name always gets the same id, so cached recipes keep their identity.
    private static func deterministicID(_ name: String) -> String {
        let bytes = Array(SHA256.hash(data: Data(name.lowercased().utf8))).prefix(16)
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                     hex.dropFirst(16).prefix(4), hex.dropFirst(20).prefix(12)]
        return parts.map(String.init).joined(separator: "-")
    }

    // MARK: - Cache

    private struct Cache: Codable {
        let key: String
        let recipes: [Recipe]
        /// nil in caches written before recipe search existed (those were on-device).
        var source: DiscoverySource? = nil
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

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
