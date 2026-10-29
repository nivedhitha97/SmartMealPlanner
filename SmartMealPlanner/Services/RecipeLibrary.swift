//
//  RecipeLibrary.swift
//  SmartMealPlanner
//
//  The recipes the app plans with: human-written recipes from the Wikibooks Cookbook (CC BY-SA 4.0), imported weekly
//  by scripts/recipes into the feed's recipes.json (see .github/workflows/grocery-feed.yml). Each is credited to its
//  authors and linked to the page revision it came from. The app downloads the file at most once a day and keeps it
//  for offline use; with no copy at all it has no recipes (never samples).
//

import Foundation

/// A recipe as recipes.json holds it (see scripts/recipes/build.py).
struct FeedRecipe: Decodable {
    struct Ingredient: Decodable {
        let name: String
        let grams: Int
        let caloriesPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double
        let pricePer100g: Double
    }

    let id: String
    let name: String
    let cuisine: String
    let servings: Int
    let totalMinutes: Int?
    let meals: [String]?
    let ingredients: [Ingredient]
    let steps: [String]
    let originalIngredients: [String]?
    let sourceName: String
    let sourceURL: String
    let authorsURL: String?
    let license: String
    let licenseURL: String
    let changes: String?
    let imageURL: String?
    let imageAuthor: String?
    let imageLicense: String?
    let imageLicenseURL: String?
    let imageSourceURL: String?

    var recipe: Recipe {
        let search = "https://www.youtube.com/results?search_query="
            + ((name + " recipe").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        return Recipe(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            cuisine: cuisine,
            ingredients: ingredients.map {
                RecipeIngredient(
                    ingredient: SmartMealPlanner.Ingredient(
                        name: $0.name, calories: $0.caloriesPer100g, protein: $0.proteinPer100g, carbs: $0.carbsPer100g,
                        fat: $0.fatPer100g, defaultPrice: $0.pricePer100g),
                    quantity: Double($0.grams))
            },
            servings: servings,
            instructions: steps,
            imageURL: imageAuthor == nil ? nil : imageURL,  // a photo is only shown with its credit
            youtubeURL: search,
            cookbookReference: sourceName,
            cookbookURL: sourceURL,
            meals: meals?.isEmpty == false ? meals : nil,
            readyInMinutes: totalMinutes,
            originalIngredients: originalIngredients,
            credit: RecipeCredit(sourceName: sourceName, sourceURL: sourceURL, authorsURL: authorsURL, license: license,
                                 licenseURL: licenseURL, changes: changes, imageAuthor: imageAuthor,
                                 imageLicense: imageLicense, imageLicenseURL: imageLicenseURL,
                                 imageSourceURL: imageSourceURL)
        )
    }

    /// The recipes in a recipes.json file.
    static func recipes(from data: Data) throws -> [Recipe] {
        struct File: Decodable { let recipes: [FeedRecipe] }
        return try JSONDecoder().decode(File.self, from: data).recipes.map(\.recipe)
    }
}

protocol RecipeLibrary {
    /// Every recipe the app can plan with. Throws when there is no copy and the feed can't be reached.
    func recipes() async throws -> [Recipe]
    /// The recipes kept on this phone, without any request (e.g. for ingredient names); empty when there are none.
    func savedRecipes() -> [Recipe]
}

final class RemoteRecipeLibrary: RecipeLibrary {
    /// The downloaded recipes are checked for an update at most this often.
    static let refreshInterval: TimeInterval = 24 * 3600
    static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "recipes.json")

    private let url: URL
    private let fileURL: URL
    private let session: URLSession
    private let now: () -> Date
    private var memory: [Recipe]?

    init(baseURL: URL = RemoteGroceryDataService.defaultBaseURL, fileURL: URL = RemoteRecipeLibrary.defaultFileURL,
         session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        url = baseURL.appending(path: "recipes.json")
        self.fileURL = fileURL
        self.session = session
        self.now = now
    }

    func recipes() async throws -> [Recipe] {
        let saved = savedRecipes()
        let age = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { now().timeIntervalSince($0) } ?? .infinity
        if !saved.isEmpty, age < Self.refreshInterval { return saved }
        do {
            let request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let recipes = try FeedRecipe.recipes(from: data)
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
            memory = recipes
            return recipes
        } catch {
            if !saved.isEmpty { return saved }  // offline: the copy on the phone, however old
            throw error
        }
    }

    func savedRecipes() -> [Recipe] {
        if let memory { return memory }
        let recipes = (try? Data(contentsOf: fileURL)).flatMap { try? FeedRecipe.recipes(from: $0) } ?? []
        memory = recipes.isEmpty ? nil : recipes
        return recipes
    }
}

/// For UI tests: the fixed recipes in Data/UITestRecipes.json, never shown to users.
struct FixtureRecipeLibrary: RecipeLibrary {
    func recipes() async throws -> [Recipe] { savedRecipes() }
    func savedRecipes() -> [Recipe] { (try? JSONLoader.load("UITestRecipes", as: [Recipe].self)) ?? [] }
}
