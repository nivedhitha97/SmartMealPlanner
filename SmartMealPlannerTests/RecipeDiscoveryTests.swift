//
//  RecipeDiscoveryTests.swift
//  SmartMealPlannerTests
//
//  Recipe discovery: published recipes from recipe search, with stand-ins for the search and the dish ideas.
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

/// Stands in for the recipe-search function.
final class FakeRecipeSearch: RecipeSearching {
    static var off: FakeRecipeSearch { FakeRecipeSearch(isConfigured: false) }

    let isConfigured: Bool
    var result: Result<[Recipe], Error>
    private(set) var calls = 0
    private(set) var lastIdeas: [String] = []

    init(isConfigured: Bool = true, result: Result<[Recipe], Error> = .success([])) {
        self.isConfigured = isConfigured
        self.result = result
    }

    func search(for preferences: UserPreferences, ideas: [String]) async throws -> [Recipe] {
        calls += 1
        lastIdeas = ideas
        return try result.get()
    }
}

@MainActor
@Suite("Recipe discovery")
struct RecipeDiscoveryTests {

    private let cache = FileManager.default.temporaryDirectory.appending(path: "searched-recipes-\(UUID().uuidString).json")

    private func preferences(allergies: [String] = []) -> UserPreferences {
        var preferences = Fixtures.preferences(diet: "Vegan", cuisines: ["Indian"], allergies: allergies)
        preferences.people = 3
        return preferences
    }

    private func discovery(_ search: FakeRecipeSearch, ideas: FakeDishIdeas = FakeDishIdeas(),
                           now: @escaping () -> Date = Date.init) -> RecipeDiscovery {
        RecipeDiscovery(search: search, ideas: ideas, cacheURL: cache, now: now)
    }

    // MARK: - AI finds, never writes

    @Test func dishIdeasAreSentToTheSearch() async throws {
        let search = FakeRecipeSearch(result: .success(try RemoteRecipeSearch.recipes(from: searchedJSON)))
        let ideas = FakeDishIdeas(["Chana Masala", "Aloo Gobi"])

        let found = await discovery(search, ideas: ideas).recipes(for: preferences())

        #expect(search.lastIdeas == ["Chana Masala", "Aloo Gobi"])
        #expect(found.recipes.map(\.name) == ["Cauliflower Fried Rice"], "the published recipe, not the idea")
        #expect(found.recipes.allSatisfy { !$0.isAIGenerated && $0.isFromSpoonacular })
    }

    @Test func withoutIdeasTheSearchUsesThePreferencesAlone() async throws {
        let search = FakeRecipeSearch(result: .success(try RemoteRecipeSearch.recipes(from: searchedJSON)))

        let found = await discovery(search).recipes(for: preferences())

        #expect(search.calls == 1 && search.lastIdeas.isEmpty)
        #expect(found.recipes.count == 1)
    }

    @Test func withoutRecipeSearchNoRecipesAreMadeUp() async {
        let ideas = FakeDishIdeas(["Chana Masala"])
        let found = await discovery(FakeRecipeSearch.off, ideas: ideas).recipes(for: preferences())

        #expect(found.recipes.isEmpty)
        #expect(found.note == RecipeDiscovery.notSetUpNote)
        #expect(ideas.calls == 0, "no point asking for ideas with nothing to search")
    }

    @Test func dishIdeasAreTidied() {
        let names = ["  Chana Masala ", "", "chana masala", "Aloo Gobi", String(repeating: "x", count: 41)]
        #expect(OnDeviceDishIdeas.cleaned(names) == ["Chana Masala", "Aloo Gobi"])
        #expect(OnDeviceDishIdeas.cleaned((1...12).map { "Dish \($0)" }).count == 8)
    }

    @Test func ideasPromptCarriesThePreferences() {
        let prompt = OnDeviceDishIdeas.prompt(for: preferences(allergies: ["peanut"]))

        #expect(prompt.contains("3 people"))
        #expect(prompt.contains("Diet: Vegan"))
        #expect(prompt.contains("Indian"))
        #expect(prompt.contains("peanut"))
    }

    // MARK: - Recipe search (Spoonacular)

    private var searchedJSON: Data {
        Data("""
        {"recipes": [{"spoonacularId": 716426, "name": "Cauliflower Fried Rice", "cuisine": "Indian", "servings": 4,
          "prepMinutes": 10, "cookMinutes": 20, "steps": ["Rice the cauliflower", "Fry with the rice"],
          "imageURL": "https://img.spoonacular.com/716426.jpg",
          "sourceURL": "https://fullbellysisters.blogspot.com/cauliflower-fried-rice", "sourceName": "Full Belly Sisters",
          "meals": ["Lunch", "Dinner"], "youtubeURL": "https://www.youtube.com/watch?v=abcdefghijk",
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
        #expect(!recipe.isAIGenerated && recipe.isFromSpoonacular, "a published recipe, not an AI one")
        #expect(recipe.id == SearchedRecipe.id(for: 716426), "the same recipe keeps the same id")
        #expect(recipe.meals == ["Lunch", "Dinner"])
        #expect(recipe.youtubeURL == "https://www.youtube.com/watch?v=abcdefghijk" && recipe.hasVideo, "the video the function found")
        #expect(recipe.findRecipeLinks.isEmpty, "it links its own source")
    }

    @Test func searchRequestSendsOnlyWhatTheSearchNeeds() throws {
        let config = RecipeSearchConfig(url: "https://abc.supabase.co/functions/v1/recipe-search", appKey: "app-key")
        let request = try RemoteRecipeSearch.request(for: preferences(allergies: ["peanut"]), ideas: ["Chana Masala"],
                                                     config: config)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-app-key") == "app-key")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(Set(body.keys) == ["diet", "cuisines", "allergies", "dislikes", "people", "ideas"], "no postcode or budget")
        #expect(body["ideas"] as? [String] == ["Chana Masala"])
        #expect(body["diet"] as? String == "Vegan" && body["people"] as? Int == 3)
        #expect(body["allergies"] as? [String] == ["peanut"])
    }

    @Test func searchIsOffWithoutAnHTTPSAddressAndKey() {
        #expect(!RemoteRecipeSearch(config: RecipeSearchConfig(url: "", appKey: "")).isConfigured)
        #expect(!RemoteRecipeSearch(config: RecipeSearchConfig(url: "http://abc.supabase.co/x", appKey: "k")).isConfigured)
        #expect(!RemoteRecipeSearch(config: RecipeSearchConfig(url: "https://abc.supabase.co/x", appKey: "")).isConfigured)
        #expect(RemoteRecipeSearch(config: RecipeSearchConfig(url: "https://abc.supabase.co/x", appKey: "k")).isConfigured)
    }

    @Test func searchedRecipesAreCachedUntilThePreferencesChange() async throws {
        let search = FakeRecipeSearch(result: .success(try RemoteRecipeSearch.recipes(from: searchedJSON)))
        let discovery = discovery(search)

        _ = await discovery.recipes(for: preferences())
        var richer = preferences()
        richer.budgetWeekly = 120  // budget doesn't change which recipes fit
        _ = await discovery.recipes(for: richer)
        #expect(search.calls == 1)

        _ = await discovery.recipes(for: preferences(allergies: ["soy"]))
        #expect(search.calls == 2, "new allergies need new recipes")
    }

    @Test func searchedRecipesBreakingAllergiesAreDropped() async throws {
        let searched = try RemoteRecipeSearch.recipes(from: searchedJSON)
        let discovery = discovery(FakeRecipeSearch(result: .success(searched)))

        let found = await discovery.recipes(for: preferences(allergies: ["rice"]))

        #expect(found.recipes.isEmpty)
        #expect(found.note == "No recipe matched all your preferences.")
    }

    @Test func offlineWithNothingSavedSaysSo() async {
        let search = FakeRecipeSearch(result: .failure(URLError(.notConnectedToInternet)))
        let found = await discovery(search).recipes(for: preferences())

        #expect(found.recipes.isEmpty)
        #expect(found.note == RecipeDiscovery.offlineNote)
    }

    @Test func serverTroubleIsNotCalledOffline() async {
        let search = FakeRecipeSearch(result: .failure(RemoteRecipeSearch.SearchError.server(502, nil)))
        let found = await discovery(search).recipes(for: preferences())

        #expect(found.note == "Couldn't reach recipe search; try again later.")
    }

    @Test func savedRecipesAreSearchedAgainAfterAWeek() async throws {
        let searched = try RemoteRecipeSearch.recipes(from: searchedJSON)
        let search = FakeRecipeSearch(result: .success(searched))
        var today = Fixtures.now
        let discovery = discovery(search, now: { today })

        _ = await discovery.recipes(for: preferences())
        today = Fixtures.date(daysFromNow: 6)
        _ = await discovery.recipes(for: preferences())
        #expect(search.calls == 1, "still fresh after 6 days")

        today = Fixtures.date(daysFromNow: 8)
        _ = await discovery.recipes(for: preferences())
        #expect(search.calls == 2, "a new search for new recipes after a week")
    }

    @Test func offlineTheSavedRecipesAreUsedHoweverOld() async throws {
        let searched = try RemoteRecipeSearch.recipes(from: searchedJSON)
        let search = FakeRecipeSearch(result: .success(searched))
        var today = Fixtures.now
        let discovery = discovery(search, ideas: FakeDishIdeas(["Chana Masala"]), now: { today })
        _ = await discovery.recipes(for: preferences())

        search.result = .failure(URLError(.notConnectedToInternet))
        today = Fixtures.date(daysFromNow: 30)
        let found = await discovery.recipes(for: preferences())

        #expect(found.recipes.map(\.name) == ["Cauliflower Fried Rice"], "the stored recipes")
        #expect(found.note == nil)
        #expect(discovery.savedRecipes().map(\.name) == ["Cauliflower Fried Rice"])
    }

    @Test func searchedBreakfastsFromOtherCuisinesAreKept() async throws {
        var breakfast = Fixtures.recipe("Shakshuka", cuisine: "Middle Eastern",
                                        ingredients: [(Fixtures.ingredient("Eggplant"), 200), (Fixtures.ingredient("Tomato"), 200)])
        breakfast.meals = ["Breakfast"]
        let discovery = discovery(FakeRecipeSearch(result: .success([breakfast])))

        let found = await discovery.recipes(for: preferences())  // Indian only

        #expect(found.recipes.map(\.name) == ["Shakshuka"], "the planner decides which cuisines a meal may come from")
    }

    @Test func plannerNoteCreditsTheOriginals() {
        #expect(RecipeDiscovery.plannerNote.hasPrefix("Recipes from Spoonacular"))
        #expect(!RecipeDiscovery.plannerNote.contains("AI"))
    }
}
