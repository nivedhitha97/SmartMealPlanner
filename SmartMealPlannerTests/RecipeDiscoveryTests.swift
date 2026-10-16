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
        let discovery = RecipeDiscovery(generator: generator, cacheURL: cache)

        let found = await discovery.recipes(for: preferences(allergies: ["peanut"]))

        #expect(found.recipes.map(\.name) == ["Chickpea Curry"])
    }

    @Test func recipesAreCachedUntilThePreferencesChange() async {
        let generator = FakeRecipeGenerator(recipes: [curry])
        let discovery = RecipeDiscovery(generator: generator, cacheURL: cache)

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
        let found = await RecipeDiscovery(generator: generator, cacheURL: cache).recipes(for: preferences())

        #expect(found.recipes.isEmpty)
        #expect(found.note == "Turn on Apple Intelligence")
        #expect(generator.calls == 0)
    }

    @Test func promptCarriesThePreferences() async {
        let generator = FakeRecipeGenerator(recipes: [curry])
        _ = await RecipeDiscovery(generator: generator, cacheURL: cache).recipes(for: preferences(allergies: ["peanut"]))

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
}
