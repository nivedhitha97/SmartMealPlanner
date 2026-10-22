//
//  RecipeSearchService.swift
//  SmartMealPlanner
//
//  Recipe search: genuine, human-made recipes from Spoonacular through the recipe-search Supabase Edge Function
//  (supabase/functions/recipe-search), in the app's format but otherwise unchanged. The Spoonacular and YouTube keys
//  stay on the server; the app only knows the function's address and an app key, from Data/RecipeSearch.json.
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
    /// - Parameter ideas: dish names to look for (from the on-device model); empty to search by preferences alone.
    func search(for preferences: UserPreferences, ideas: [String]) async throws -> [Recipe]
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
    /// "Breakfast", or "Lunch" and "Dinner".
    let meals: [String]?
    let imageURL: String?
    let sourceURL: String?
    let sourceName: String?
    /// A real video for the dish, when the function could look one up on YouTube.
    let youtubeURL: String?

    /// The app's recipe, crediting Spoonacular and linking to the original (Spoonacular's terms ask for both), with
    /// the YouTube video the function found (else the YouTube search the recipe already has).
    var recipe: Recipe {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let video = youtubeURL.flatMap(URL.init(string:)).flatMap { YouTubeLink.isYouTube($0) ? $0.absoluteString : nil }
        let search = "https://www.youtube.com/results?search_query="
            + ((trimmedName + " recipe").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        return Recipe(
            id: Self.id(for: spoonacularId),
            name: trimmedName,
            cuisine: cuisine,
            ingredients: ingredients.map {
                RecipeIngredient(
                    ingredient: SmartMealPlanner.Ingredient(
                        name: $0.name, calories: $0.caloriesPer100g, protein: $0.proteinPer100g, carbs: $0.carbsPer100g,
                        fat: $0.fatPer100g, defaultPrice: $0.pricePer100g),
                    quantity: Double($0.grams))
            },
            servings: servings,
            prepMinutes: prepMinutes,
            cookMinutes: cookMinutes,
            instructions: steps,
            imageURL: imageURL,
            youtubeURL: video ?? search,
            cookbookReference: "Spoonacular" + (sourceName.map { " · \($0)" } ?? ""),
            cookbookURL: sourceURL ?? "https://spoonacular.com/recipes/-\(spoonacularId)",
            meals: meals?.isEmpty == false ? meals : nil
        )
    }

    /// The same Spoonacular recipe always gets the same id, so saved plans keep pointing at it.
    static func id(for spoonacularId: Int) -> UUID {
        let hex = String(format: "%012X", spoonacularId)
        return UUID(uuidString: "5F00ACA1-0000-4000-8000-\(hex.suffix(12))") ?? UUID()
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

    func search(for preferences: UserPreferences, ideas: [String]) async throws -> [Recipe] {
        let request = try Self.request(for: preferences, ideas: ideas, config: config)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw SearchError.server(status, message)
        }
        return try Self.recipes(from: data)
    }

    /// Only what the search needs: diet, cuisines, allergies, dislikes, people and dish ideas (no postcode or budget).
    static func request(for preferences: UserPreferences, ideas: [String] = [],
                        config: RecipeSearchConfig) throws -> URLRequest {
        guard let endpoint = config.endpoint else { throw SearchError.notConfigured }
        var request = URLRequest(url: endpoint, timeoutInterval: 60)  // several Spoonacular searches
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appKey, forHTTPHeaderField: "x-app-key")
        let body: [String: Any] = [
            "diet": preferences.dietType, "cuisines": preferences.cuisines, "allergies": preferences.allergies,
            "dislikes": preferences.dislikes, "people": preferences.people, "ideas": ideas,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    static func recipes(from data: Data) throws -> [Recipe] {
        struct Response: Decodable { let recipes: [SearchedRecipe] }
        return try JSONDecoder().decode(Response.self, from: data).recipes.map(\.recipe)
    }
}
