//
//  RecipeDiscoveryTests.swift
//  SmartMealPlannerTests
//
//  Recipe discovery: the Wikibooks recipes, with stand-ins for the library and the dish ideas.
//

import Foundation
import Testing
@testable import SmartMealPlanner

/// Suggests canned dish names and records what it was asked.
final class FakeDishIdeas: DishIdeaSuggesting {
    var dishes: [String]
    private(set) var calls = 0

    init(_ dishes: [String] = []) {
        self.dishes = dishes
    }

    func ideas(for preferences: UserPreferences) async -> [String] {
        calls += 1
        return dishes
    }
}

/// Stands in for the recipe library (the Wikibooks recipes in the feed).
final class FakeRecipeLibrary: RecipeLibrary {
    var result: Result<[Recipe], Error>
    private(set) var calls = 0

    init(_ result: Result<[Recipe], Error> = .success([])) {
        self.result = result
    }

    func recipes() async throws -> [Recipe] {
        calls += 1
        return try result.get()
    }

    func savedRecipes() -> [Recipe] { (try? result.get()) ?? [] }
}

@MainActor
@Suite("Recipe discovery")
struct RecipeDiscoveryTests {

    private func preferences(allergies: [String] = [], cuisines: [String] = ["Indian"]) -> UserPreferences {
        var preferences = Fixtures.preferences(diet: "Vegan", cuisines: cuisines, allergies: allergies)
        preferences.people = 3
        return preferences
    }

    private func dish(_ name: String, cuisine: String = "Indian", meals: [String] = ["Lunch", "Dinner"],
                      ingredients: [String] = ["Chickpeas", "Tomatoes"]) -> Recipe {
        var recipe = Fixtures.recipe(name, cuisine: cuisine,
                                     ingredients: ingredients.map { (Fixtures.ingredient($0), 100) })
        recipe.meals = meals
        return recipe
    }

    private var feedJSON: Data {
        Data("""
        {"recipes": [{"id": "6F1B2C3D-0000-5000-8000-000000000001", "name": "Potato Curry (Aloo Masala)",
          "cuisine": "Indian", "servings": 4, "totalMinutes": 20, "meals": ["Lunch", "Dinner"],
          "steps": ["Heat oil.", "Add potatoes."], "originalIngredients": ["4 large potatoes", "1 tablespoon oil"],
          "ingredients": [
            {"name": "Potatoes", "grams": 1108, "caloriesPer100g": 77, "proteinPer100g": 2, "carbsPer100g": 17.5,
             "fatPer100g": 0.1, "pricePer100g": 0.15},
            {"name": "Vegetable Oil", "grams": 14, "caloriesPer100g": 884, "proteinPer100g": 0, "carbsPer100g": 0,
             "fatPer100g": 100, "pricePer100g": 0.35}],
          "sourceName": "Wikibooks Cookbook",
          "sourceURL": "https://en.wikibooks.org/w/index.php?title=Cookbook%3APotato_Curry&oldid=4615205",
          "authorsURL": "https://en.wikibooks.org/w/index.php?title=Cookbook%3APotato_Curry&action=history",
          "license": "CC BY-SA 4.0", "licenseURL": "https://creativecommons.org/licenses/by-sa/4.0/",
          "changes": "Adapted for Smart Meal Planner: amounts converted to grams.",
          "imageURL": "https://upload.wikimedia.org/x.jpg", "imageAuthor": "Thamizhpparithi Maari",
          "imageLicense": "CC BY-SA 4.0", "imageLicenseURL": "https://creativecommons.org/licenses/by-sa/4.0",
          "imageSourceURL": "https://commons.wikimedia.org/wiki/File:X.jpg"}]}
        """.utf8)
    }

    // MARK: - The Wikibooks recipes

    @Test func feedRecipesBecomeCreditedAppRecipes() throws {
        let recipe = try #require(FeedRecipe.recipes(from: feedJSON).first)

        #expect((recipe.name, recipe.cuisine, recipe.servings, recipe.totalMinutes, recipe.hasTimeSplit)
                == ("Potato Curry (Aloo Masala)", "Indian", 4, 20, false), "only the total time is known")
        #expect(recipe.ingredients.map(\.quantity) == [1108, 14])
        #expect(recipe.ingredients[0].ingredient.defaultPrice == 0.15)
        #expect(recipe.instructions == ["Heat oil.", "Add potatoes."], "the authors' own steps")
        #expect(recipe.originalIngredients == ["4 large potatoes", "1 tablespoon oil"])
        #expect(recipe.isFromWikibooks && !recipe.isAIGenerated)
        #expect(recipe.credit?.license == "CC BY-SA 4.0")
        #expect(recipe.credit?.authorsURL?.hasSuffix("action=history") == true, "the authors are credited")
        #expect(recipe.cookbookURL?.contains("oldid=4615205") == true, "the exact revision it came from")
        #expect(recipe.credit?.imageAuthor == "Thamizhpparithi Maari" && recipe.imageURL != nil)
        #expect(recipe.youtubeURL?.hasPrefix("https://www.youtube.com/results?search_query=") == true,
                "a YouTube search link, no YouTube API")
        #expect(recipe.id == UUID(uuidString: "6F1B2C3D-0000-5000-8000-000000000001"), "the same id every week")
    }

    @Test func aPhotoWithoutACreditIsNotShown() throws {
        let json = String(decoding: feedJSON, as: UTF8.self)
            .replacingOccurrences(of: "\"imageAuthor\": \"Thamizhpparithi Maari\",", with: "")
        let recipe = try #require(FeedRecipe.recipes(from: Data(json.utf8)).first)
        #expect(recipe.imageURL == nil)
    }

    @Test func recipesFitThePreferencesAndBreakfastsComeFromAnyCuisine() async {
        let library = FakeRecipeLibrary(.success([
            dish("Chana Masala"),
            dish("Butter Chicken", ingredients: ["Chicken Breast", "Butter"]),
            dish("Pasta Arrabbiata", cuisine: "Italian"),
            dish("Shakshuka", cuisine: "International", meals: ["Breakfast"], ingredients: ["Tomatoes", "Onion"]),
            dish("Peanut Noodles", ingredients: ["Peanut Butter", "Noodles"]),
        ]))
        let found = await RecipeDiscovery(library: library, ideas: NoDishIdeas())
            .recipes(for: preferences(allergies: ["peanut"]))

        #expect(Set(found.recipes.map(\.name)) == ["Chana Masala", "Shakshuka"],
                "vegan, no peanut, Indian lunches and dinners, breakfast from any cuisine")
        #expect(found.note == nil)
    }

    @Test func dishIdeasComeFirst() {
        let recipes = (1...10).map { dish("Dish \($0)") } + [dish("Aloo Gobi"), dish("Chana Masala Curry")]
        let ranked = RecipeDiscovery.ranked(recipes, ideas: ["Chana Masala", "Aloo Gobi"])
        #expect(Set(ranked.prefix(2).map(\.name)) == ["Aloo Gobi", "Chana Masala Curry"])
        #expect(ranked.count == recipes.count)
    }

    @Test func dishIdeasAreTidied() {
        let names = ["  Chana Masala ", "", "chana masala", "Aloo Gobi", String(repeating: "x", count: 41)]
        #expect(OnDeviceDishIdeas.cleaned(names) == ["Chana Masala", "Aloo Gobi"])
        #expect(OnDeviceDishIdeas.cleaned((1...12).map { "Dish \($0)" }).count == 8)
    }

    @Test func ideasPromptCarriesThePreferences() {
        let prompt = OnDeviceDishIdeas.prompt(for: preferences(allergies: ["peanut"]))
        #expect(prompt.contains("3 people") && prompt.contains("Diet: Vegan") && prompt.contains("Indian")
                && prompt.contains("peanut"))
    }

    @Test func offlineWithNoRecipesSaysSo() async {
        let found = await RecipeDiscovery(library: FakeRecipeLibrary(.failure(URLError(.notConnectedToInternet))),
                                          ideas: NoDishIdeas()).recipes(for: preferences())
        #expect(found.recipes.isEmpty && found.note == RecipeDiscovery.offlineNote)

        let down = await RecipeDiscovery(library: FakeRecipeLibrary(.failure(URLError(.badServerResponse))),
                                         ideas: NoDishIdeas()).recipes(for: preferences())
        #expect(down.note == RecipeDiscovery.unreachableNote)
    }

    @Test func noMatchingRecipeIsExplained() async {
        let library = FakeRecipeLibrary(.success([dish("Butter Chicken", ingredients: ["Chicken Breast"])]))
        let found = await RecipeDiscovery(library: library, ideas: NoDishIdeas()).recipes(for: preferences())
        #expect(found.recipes.isEmpty && found.note == RecipeDiscovery.noMatchNote)
    }

    @Test func plannerNoteCreditsTheAuthors() {
        #expect(RecipeDiscovery.plannerNote.contains("Wikibooks Cookbook"))
        #expect(RecipeDiscovery.plannerNote.contains("CC BY-SA 4.0"))
    }

    // MARK: - The library on the phone

    @Test func theLibraryKeepsItsCopyForOfflineUse() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "recipes-\(UUID().uuidString).json")
        try feedJSON.write(to: file)
        let offline = RemoteRecipeLibrary(baseURL: URL(string: "https://invalid.invalid/")!, fileURL: file,
                                          now: { Date.distantFuture })
        let recipes = try await offline.recipes()
        #expect(recipes.map(\.name) == ["Potato Curry (Aloo Masala)"], "can't download: the copy, however old")
        #expect(offline.savedRecipes().count == 1)
    }

    // MARK: - Earlier versions' data

    @Test func spoonacularAndAIRecipesFromEarlierVersionsAreRemoved() throws {
        let storage = IsolatedDefaults()
        let folder = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in LegacyDataCleanup.oldRecipeFiles {
            try Data("[]".utf8).write(to: folder.appending(path: name))
        }
        var spoonacular = dish("Cauliflower Fried Rice")
        spoonacular.cookbookReference = "Spoonacular · Full Belly Sisters"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plan = Fixtures.plan(days: [Fixtures.day(Fixtures.now, lunch: spoonacular)])
        storage.defaults.set(try encoder.encode(plan), forKey: PlanningViewModel.Keys.lastPlan)

        LegacyDataCleanup.run(defaults: storage.defaults, folder: folder)

        #expect(storage.defaults.data(forKey: PlanningViewModel.Keys.lastPlan) == nil)
        for name in LegacyDataCleanup.oldRecipeFiles {
            #expect(!FileManager.default.fileExists(atPath: folder.appending(path: name).path()))
        }
        let ok = Fixtures.plan(days: [Fixtures.day(Fixtures.now, lunch: dish("Chana Masala"))])
        #expect(!LegacyDataCleanup.planHasOldRecipes(try encoder.encode(ok)), "a plan of current recipes stays")
    }
}
