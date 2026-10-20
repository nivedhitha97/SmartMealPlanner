//
//  RecipeSearchService.swift
//  SmartMealPlanner
//
//  Recipe search: real recipes from Spoonacular, adapted by Claude Haiku to the app's format, through the
//  recipe-search Supabase Edge Function (supabase/functions/recipe-search). The Spoonacular and Anthropic keys stay
//  on the server; the app only knows the function's address and an app key, from Data/RecipeSearch.json.
//

import Foundation

/// Where the recipe-search function is. Both values empty (the default) turns the search off.
struct RecipeSearchConfig: Decodable, Equatable {
    var url: String
    var appKey: String

    var endpoint: URL? {
        guard !appKey.isEmpty, let url = URL(string: url), url.scheme == "https" else { return nil }
        return url
    }

    static let bundled: RecipeSearchConfig = (try? JSONLoader.load("RecipeSearch", as: RecipeSearchConfig.self))
        ?? RecipeSearchConfig(url: "", appKey: "")
}

protocol RecipeSearching {
    /// Whether a search can be made at all (the function is configured).
    var isConfigured: Bool { get }
    func search(for preferences: UserPreferences) async throws -> [Recipe]
}

/// A recipe as the function returns it (see `AppRecipe` in logic.ts).
struct SearchedRecipe: Decodable {
    struct Ingredient: Decodable {
        let name: String
        let grams: Int
        let caloriesPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double
        let pricePer100g: Double
    }

    let spoonacularId: Int
    let name: String
    let cuisine: String
    let servings: Int
    let prepMinutes: Int
    let cookMinutes: Int
    let ingredients: [Ingredient]
    let steps: [String]
    let imageURL: String?
    let sourceURL: String?
    let sourceName: String?

    /// The app's recipe, crediting Spoonacular and linking to the original (Spoonacular's terms ask for both).
    var recipe: Recipe {
        let generated = GeneratedRecipe(
            name: name, cuisine: cuisine, servings: servings, prepMinutes: prepMinutes, cookMinutes: cookMinutes,
            ingredients: ingredients.map {
                GeneratedIngredient(name: $0.name, grams: $0.grams, caloriesPer100g: Int($0.caloriesPer100g.rounded()),
                                    proteinPer100g: $0.proteinPer100g, carbsPer100g: $0.carbsPer100g,
                                    fatPer100g: $0.fatPer100g, pricePer100g: $0.pricePer100g)
            },
            steps: steps)
        var recipe = RecipeDiscovery.recipe(from: generated)
        recipe.imageURL = imageURL
        recipe.cookbookReference = "Spoonacular" + (sourceName.map { " · \($0)" } ?? "")
        recipe.cookbookURL = sourceURL ?? "https://spoonacular.com/recipes/-\(spoonacularId)"
        return recipe
    }
}

struct RemoteRecipeSearch: RecipeSearching {
    enum SearchError: Error, Equatable {
        case notConfigured
        case server(Int, String?)
    }

    var config: RecipeSearchConfig = .bundled
    var session: URLSession = .shared

    var isConfigured: Bool { config.endpoint != nil }

    func search(for preferences: UserPreferences) async throws -> [Recipe] {
        let request = try Self.request(for: preferences, config: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw SearchError.server(status, message)
        }
        return try Self.recipes(from: data)
    }

    /// Only what the search needs: diet, cuisines, allergies, dislikes and people (no postcode or budget).
    static func request(for preferences: UserPreferences, config: RecipeSearchConfig) throws -> URLRequest {
        guard let endpoint = config.endpoint else { throw SearchError.notConfigured }
        var request = URLRequest(url: endpoint, timeoutInterval: 90)  // Spoonacular and Claude can take a while
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appKey, forHTTPHeaderField: "x-app-key")
        let body: [String: Any] = [
            "diet": preferences.dietType, "cuisines": preferences.cuisines, "allergies": preferences.allergies,
            "dislikes": preferences.dislikes, "people": preferences.people,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static func recipes(from data: Data) throws -> [Recipe] {
        struct Response: Decodable { let recipes: [SearchedRecipe] }
        return try JSONDecoder().decode(Response.self, from: data).recipes.map(\.recipe)
    }
}
