//
//  RecipeDiscoveryTests.swift
//  SmartMealPlannerTests
//
//  AI recipe discovery with a stand-in for the on-device model.
//

import Foundation
import Testing
@testable import SmartMealPlanner

/// Returns canned recipes and counts how often it was asked.
final class FakeRecipeGenerator: RecipeGenerating {
    var availability: RecipeDiscoveryAvailability
    var recipes: [GeneratedRecipe]
    private(set) var calls = 0
    private(set) var lastPrompt = ""

    init(availability: RecipeDiscoveryAvailability = .available, recipes: [GeneratedRecipe]) {
        self.availability = availability
        self.recipes = recipes
    }

    func generate(prompt: String, instructions: String) async throws -> [GeneratedRecipe] {
        calls += 1
        lastPrompt = prompt
        return recipes
    }
}

/// Stands in for the recipe-search function.
final class FakeRecipeSearch: RecipeSearching {
    static var off: FakeRecipeSearch { FakeRecipeSearch(isConfigured: false) }

    let isConfigured: Bool
    var result: Result<[Recipe], Error>
    private(set) var calls = 0

    init(isConfigured: Bool = true, result: Result<[Recipe], Error> = .success([])) {
        self.isConfigured = isConfigured
        self.result = result
    }

    func search(for preferences: UserPreferences) async throws -> [Recipe] {
        calls += 1
        return try result.get()
    }
}

@MainActor
@Suite("Recipe discovery")
struct RecipeDiscoveryTests {

    private let cache = FileManager.default.temporaryDirectory.appending(path: "ai-recipes-\(UUID().uuidString).json")

    private func ingredient(_ name: String, grams: Int = 200) -> GeneratedIngredient {
        GeneratedIngredient(name: name, grams: grams, caloriesPer100g: 120, proteinPer100g: 8, carbsPer100g: 15,
                            fatPer100g: 3, pricePer100g: 0.5)
    }

    private func recipe(_ name: String, _ ingredients: [String], cuisine: String = "Indian") -> GeneratedRecipe {
        GeneratedRecipe(name: name, cuisine: cuisine, servings: 2, prepMinutes: 10, cookMinutes: 25,
                        ingredients: ingredients.map { ingredient($0) }, steps: ["Chop", "Cook", "Serve"])
    }

    private var curry: GeneratedRecipe { recipe("Chickpea Curry", ["Chickpeas", "Spinach", "Rice"]) }
    private var satay: GeneratedRecipe { recipe("Tofu Satay", ["Tofu", "Peanut Butter"]) }

    private func preferences(allergies: [String] = []) -> UserPreferences {
        var preferences = Fixtures.preferences(diet: "Vegan", cuisines: ["Indian"], allergies: allergies)
        preferences.people = 3
        return preferences
    }

    @Test func generatedRecipesBecomeAppRecipes() {
        let made = RecipeDiscovery.recipe(from: curry)

        #expect(made.isAIGenerated)
        #expect((made.name, made.cuisine, made.servings, made.prepMinutes, made.cookMinutes)
                == ("Chickpea Curry", "Indian", 2, 10, 25))
        #expect(made.ingredients.map(\.ingredient.name) == ["Chickpeas", "Spinach", "Rice"])
        #expect(made.ingredients[0].quantity == 200 && made.ingredients[0].ingredient.defaultPrice == 0.5)
        #expect(made.instructions.count == 3)
        #expect(made.id == RecipeDiscovery.recipe(from: curry).id, "the same dish keeps the same id")
    }

    @Test func recipesBreakingAllergiesAreDropped() async {
        let generator = FakeRecipeGenerator(recipes: [curry, satay])
        let discovery = RecipeDiscovery(search: FakeRecipeSearch.off, generator: generator, cacheURL: cache)

        let found = await discovery.recipes(for: preferences(allergies: ["peanut"]))

        #expect(found.recipes.map(\.name) == ["Chickpea Curry"])
    }

    @Test func recipesAreCachedUntilThePreferencesChange() async {
        let generator = FakeRecipeGenerator(recipes: [curry])
        let discovery = RecipeDiscovery(search: FakeRecipeSearch.off, generator: generator, cacheURL: cache)

        _ = await discovery.recipes(for: preferences())
        var richer = preferences()
        richer.budgetWeekly = 120  // budget doesn't change which recipes fit
        _ = await discovery.recipes(for: richer)
        #expect(generator.calls == 1)

        _ = await discovery.recipes(for: preferences(allergies: ["soy"]))
        #expect(generator.calls == 2, "new allergies need new recipes")
    }

    @Test func unavailableModelExplainsWhy() async {
        let generator = FakeRecipeGenerator(availability: .unavailable("Turn on Apple Intelligence"), recipes: [curry])
        let found = await RecipeDiscovery(search: FakeRecipeSearch.off, generator: generator, cacheURL: cache).recipes(for: preferences())

        #expect(found.recipes.isEmpty)
        #expect(found.note == "Turn on Apple Intelligence")
        #expect(generator.calls == 0)
    }

    @Test func promptCarriesThePreferences() async {
        let generator = FakeRecipeGenerator(recipes: [curry])
        _ = await RecipeDiscovery(search: FakeRecipeSearch.off, generator: generator, cacheURL: cache).recipes(for: preferences(allergies: ["peanut"]))

        #expect(generator.lastPrompt.contains("3 people"))
        #expect(generator.lastPrompt.contains("Diet: Vegan"))
        #expect(generator.lastPrompt.contains("Indian"))
        #expect(generator.lastPrompt.contains("peanut"))
    }

    @Test func planIncludesDiscoveredRecipesOnlyWhenTurnedOn() async {
        let storage = IsolatedDefaults()
        var prefs = Fixtures.preferences()
        prefs.save(to: storage.defaults)
        MealRoutine.default.save(to: storage.defaults)
        let planner = StubPlanner(result: .success(Fixtures.plan()))
        let discovered = DiscoveredRecipes(recipes: [RecipeDiscovery.recipe(from: curry)], note: nil)
        let viewModel = PlanningViewModel(ai: planner, defaults: storage.defaults,
                                          loadCatalog: { .init(recipes: [Fixtures.recipe("Pasta")], offers: []) },
                                          discoverRecipes: { _ in discovered })

        await viewModel.generatePlan()
        #expect(planner.calls.last?.recipes.map(\.name) == ["Pasta"], "off by default")

        prefs.discoverRecipes = true
        prefs.save(to: storage.defaults)
        await viewModel.generatePlan()
        #expect(planner.calls.last?.recipes.map(\.name) == ["Pasta", "Chickpea Curry"])
        #expect(viewModel.suggestedPlan?.aiSummary.contains("discovered by on-device AI") == true)
    }

    // MARK: - Recipe search (Spoonacular + Claude Haiku)

    private var searchedJSON: Data {
        Data("""
        {"recipes": [{"spoonacularId": 716426, "name": "Cauliflower Fried Rice", "cuisine": "Indian", "servings": 4,
          "prepMinutes": 10, "cookMinutes": 20, "steps": ["Rice the cauliflower", "Fry with the rice"],
          "imageURL": "https://img.spoonacular.com/716426.jpg",
          "sourceURL": "https://fullbellysisters.blogspot.com/cauliflower-fried-rice", "sourceName": "Full Belly Sisters",
          "ingredients": [
            {"name": "Cauliflower", "grams": 600, "caloriesPer100g": 25, "proteinPer100g": 1.9, "carbsPer100g": 5,
             "fatPer100g": 0.3, "pricePer100g": 0.35},
            {"name": "Brown Rice", "grams": 390, "caloriesPer100g": 112, "proteinPer100g": 2.3, "carbsPer100g": 23.5,
             "fatPer100g": 0.8, "pricePer100g": 0.3}]}]}
        """.utf8)
    }

    @Test func searchedRecipesBecomeAppRecipesCreditingSpoonacular() throws {
        let recipe = try #require(RemoteRecipeSearch.recipes(from: searchedJSON).first)

        #expect((recipe.name, recipe.cuisine, recipe.servings, recipe.prepMinutes, recipe.cookMinutes)
                == ("Cauliflower Fried Rice", "Indian", 4, 10, 20))
        #expect(recipe.ingredients.map(\.quantity) == [600, 390])
        #expect(recipe.ingredients[1].ingredient.defaultPrice == 0.3)
        #expect(recipe.imageURL == "https://img.spoonacular.com/716426.jpg")
        #expect(recipe.cookbookReference == "Spoonacular · Full Belly Sisters")
        #expect(recipe.cookbookURL == "https://fullbellysisters.blogspot.com/cauliflower-fried-rice")
        #expect(recipe.isAIGenerated && recipe.isFromSpoonacular)
    }

    @Test func searchRequestSendsOnlyWhatTheSearchNeeds() throws {
        let config = RecipeSearchConfig(url: "https://abc.supabase.co/functions/v1/recipe-search", appKey: "app-key")
        let request = try RemoteRecipeSearch.request(for: preferences(allergies: ["peanut"]), config: config)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-app-key") == "app-key")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(Set(body.keys) == ["diet", "cuisines", "allergies", "dislikes", "people"], "no postcode or budget")
        #expect(body["diet"] as? String == "Vegan" && body["people"] as? Int == 3)
        #expect(body["allergies"] as? [String] == ["peanut"])
    }

    @Test func searchIsOffWithoutAnHTTPSAddressAndKey() {
        #expect(!RemoteRecipeSearch(config: RecipeSearchConfig(url: "", appKey: "")).isConfigured)
        #expect(!RemoteRecipeSearch(config: RecipeSearchConfig(url: "http://abc.supabase.co/x", appKey: "k")).isConfigured)
        #expect(!RemoteRecipeSearch(config: RecipeSearchConfig(url: "https://abc.supabase.co/x", appKey: "")).isConfigured)
        #expect(RemoteRecipeSearch(config: RecipeSearchConfig(url: "https://abc.supabase.co/x", appKey: "k")).isConfigured)
    }

    @Test func recipeSearchIsUsedFirstWhenSetUp() async throws {
        let searched = try RemoteRecipeSearch.recipes(from: searchedJSON)
        let search = FakeRecipeSearch(result: .success(searched))
        let generator = FakeRecipeGenerator(recipes: [curry])
        let discovery = RecipeDiscovery(search: search, generator: generator, cacheURL: cache)

        let found = await discovery.recipes(for: preferences())

        #expect(found.recipes.map(\.name) == ["Cauliflower Fried Rice"])
        #expect(found.source == .spoonacular)
        #expect(generator.calls == 0, "the on-device model isn't needed")
        #expect(discovery.availability == .available)

        _ = await discovery.recipes(for: preferences())
        #expect(search.calls == 1, "cached until the preferences change")
    }

    @Test func searchedRecipesBreakingAllergiesAreDropped() async throws {
        let searched = try RemoteRecipeSearch.recipes(from: searchedJSON)
        let discovery = RecipeDiscovery(search: FakeRecipeSearch(result: .success(searched)),
                                        generator: FakeRecipeGenerator(recipes: []), cacheURL: cache)

        let found = await discovery.recipes(for: preferences(allergies: ["rice"]))

        #expect(found.recipes.isEmpty)
        #expect(found.note == "No Spoonacular recipe matched all your preferences.")
    }

    @Test func failedSearchFallsBackToTheOnDeviceModel() async {
        let search = FakeRecipeSearch(result: .failure(RemoteRecipeSearch.SearchError.server(429, "limit")))
        let generator = FakeRecipeGenerator(recipes: [curry])
        let discovery = RecipeDiscovery(search: search, generator: generator, cacheURL: cache)

        let found = await discovery.recipes(for: preferences())

        #expect(found.recipes.map(\.name) == ["Chickpea Curry"])
        #expect(found.source == .onDevice)

        _ = await discovery.recipes(for: preferences())
        #expect(search.calls == 2, "an on-device fallback isn't kept in place of a working search")
    }

    @Test func failedSearchWithoutOnDeviceAIExplainsIt() async {
        let search = FakeRecipeSearch(result: .failure(URLError(.notConnectedToInternet)))
        let generator = FakeRecipeGenerator(availability: .unavailable("No Apple Intelligence"), recipes: [])
        let found = await RecipeDiscovery(search: search, generator: generator, cacheURL: cache).recipes(for: preferences())

        #expect(found.recipes.isEmpty)
        #expect(found.note == "Couldn't reach recipe search this time; the built-in recipes are used.")
    }

    @Test func plannerNotesSayWhereRecipesCameFrom() {
        #expect(DiscoverySource.spoonacular.description == "from Spoonacular, adapted by AI")
        #expect(DiscoverySource.onDevice.description == "discovered by on-device AI")
    }
}
