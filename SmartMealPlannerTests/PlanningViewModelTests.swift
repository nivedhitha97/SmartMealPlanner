//
//  PlanningViewModelTests.swift
//  SmartMealPlannerTests
//
//  The view model behind the Weekly plan screen: generating, caching and clearing a plan.
//

import Foundation
import Testing
@testable import SmartMealPlanner

/// Planner that returns a canned plan (or throws) and records what it was asked for.
@MainActor
final class StubPlanner: AIPlanningService {
    var result: Result<AISuggestedWeekPlan, Error>
    private(set) var calls: [(preferences: UserPreferences, routine: MealRoutine, recipes: [Recipe], offers: [SupermarketOffer],
                              prices: [IngredientPrice])] = []

    init(result: Result<AISuggestedWeekPlan, Error>) {
        self.result = result
    }

    func generateWeeklySuggestions(
        preferences: UserPreferences,
        routine: MealRoutine,
        recipes: [Recipe],
        weeklyOffers: [SupermarketOffer],
        ingredientPrices: [IngredientPrice]
    ) async throws -> AISuggestedWeekPlan {
        calls.append((preferences, routine, recipes, weeklyOffers, ingredientPrices))
        return try result.get()
    }
}

private struct PlannerFailure: LocalizedError {
    var errorDescription: String? { "Planner is unavailable" }
}

@MainActor
@Suite("Planning view model")
struct PlanningViewModelTests {

    private let storage = IsolatedDefaults()
    private let catalog = PlanningViewModel.Catalog(
        recipes: [Fixtures.recipe("Pasta")],
        offers: [Fixtures.offer(product: "Tomatoes", price: 1.19)],
        ingredientPrices: [Fixtures.ingredientPrice("Tomato", per100g: 0.41)]
    )

    private func makeViewModel(planner: StubPlanner, catalog: PlanningViewModel.Catalog? = nil) -> PlanningViewModel {
        let catalog = catalog ?? self.catalog
        return PlanningViewModel(ai: planner, defaults: storage.defaults, loadCatalog: { catalog },
                                 discoverRecipes: { _ in DiscoveredRecipes(recipes: [], note: nil) })
    }

    private func saveSetup() {
        Fixtures.preferences(budget: 70).save(to: storage.defaults)
        MealRoutine.default.save(to: storage.defaults)
    }

    @Test func startsEmptyWhenNothingIsCached() {
        let viewModel = makeViewModel(planner: StubPlanner(result: .success(Fixtures.plan())))

        #expect(viewModel.suggestedPlan == nil)
        #expect(!viewModel.isLoading)
        #expect(viewModel.lastError == nil)
    }

    @Test func generatingWithoutPreferencesAsksForThemFirst() async {
        let planner = StubPlanner(result: .success(Fixtures.plan()))
        MealRoutine.default.save(to: storage.defaults)
        let viewModel = makeViewModel(planner: planner)

        await viewModel.generatePlan()

        #expect(viewModel.lastError == PlanningViewModel.missingPreferencesMessage)
        #expect(viewModel.suggestedPlan == nil)
        #expect(planner.calls.isEmpty)
        #expect(!viewModel.isLoading)
    }

    @Test func generatingWithoutARoutineAsksForItFirst() async {
        let planner = StubPlanner(result: .success(Fixtures.plan()))
        Fixtures.preferences().save(to: storage.defaults)
        let viewModel = makeViewModel(planner: planner)

        await viewModel.generatePlan()

        #expect(viewModel.lastError == PlanningViewModel.missingRoutineMessage)
        #expect(planner.calls.isEmpty)
    }

    @Test func generatingPassesSavedSetupToThePlannerAndShowsThePlan() async throws {
        saveSetup()
        let plan = Fixtures.plan(total: 42, budget: 70)
        let planner = StubPlanner(result: .success(plan))
        let viewModel = makeViewModel(planner: planner)

        await viewModel.generatePlan()

        #expect(viewModel.suggestedPlan?.id == plan.id)
        #expect(viewModel.lastError == nil)
        #expect(!viewModel.isLoading)

        let call = try #require(planner.calls.first)
        #expect(planner.calls.count == 1)
        #expect(call.preferences.budgetWeekly == 70)
        #expect(call.routine == .default)
        #expect(call.recipes.map(\.name) == ["Pasta"])
        #expect(call.offers.map(\.productName) == ["Tomatoes"])
        #expect(call.prices.map(\.ingredientName) == ["Tomato"], "Live ingredient prices reach the planner")
    }

    @Test func generatedPlanIsRestoredNextLaunch() async {
        saveSetup()
        let plan = Fixtures.plan()
        await makeViewModel(planner: StubPlanner(result: .success(plan))).generatePlan()

        let relaunched = makeViewModel(planner: StubPlanner(result: .success(Fixtures.plan())))

        #expect(relaunched.suggestedPlan?.id == plan.id)
    }

    @Test func clearingThePlanRemovesItAndItsCache() async {
        saveSetup()
        let viewModel = makeViewModel(planner: StubPlanner(result: .success(Fixtures.plan())))
        await viewModel.generatePlan()

        viewModel.clearPlan()

        #expect(viewModel.suggestedPlan == nil)
        #expect(storage.defaults.data(forKey: PlanningViewModel.Keys.lastPlan) == nil)
        #expect(makeViewModel(planner: StubPlanner(result: .success(Fixtures.plan()))).suggestedPlan == nil)
    }

    @Test func plannerFailureIsShownAndKeepsThePreviousPlan() async {
        saveSetup()
        let first = Fixtures.plan()
        let planner = StubPlanner(result: .success(first))
        let viewModel = makeViewModel(planner: planner)
        await viewModel.generatePlan()

        planner.result = .failure(PlannerFailure())
        await viewModel.generatePlan()

        #expect(viewModel.lastError == "Planner is unavailable")
        #expect(viewModel.suggestedPlan?.id == first.id)
        #expect(!viewModel.isLoading)
    }

    @Test func catalogFailureIsShown() async {
        saveSetup()
        let viewModel = PlanningViewModel(
            ai: StubPlanner(result: .success(Fixtures.plan())),
            defaults: storage.defaults,
            loadCatalog: { throw JSONResourceError.missingFile("UITestOffers") },
            discoverRecipes: { _ in DiscoveredRecipes(recipes: [Fixtures.recipe("Pasta")], note: nil) }
        )

        await viewModel.generatePlan()

        #expect(viewModel.lastError == "Missing bundled JSON: UITestOffers.json")
        #expect(viewModel.suggestedPlan == nil)
    }

    @Test func catalogHasTheGroceryFeedButNoRecipesOfItsOwn() async throws {
        let catalog = try await PlanningViewModel.Catalog.live(from: FixtureGroceryDataService())

        #expect(catalog.recipes.isEmpty, "recipes only come from recipe search")
        #expect(!catalog.offers.isEmpty)
    }

    @Test func planUsesTheSearchedRecipes() async {
        saveSetup()
        let planner = StubPlanner(result: .success(Fixtures.plan()))
        let viewModel = PlanningViewModel(
            ai: planner, defaults: storage.defaults, loadCatalog: { .init(offers: []) },
            discoverRecipes: { _ in DiscoveredRecipes(recipes: [Fixtures.recipe("Chana Masala")], note: nil, source: .spoonacular) }
        )

        await viewModel.generatePlan()

        #expect(planner.calls.last?.recipes.map(\.name) == ["Chana Masala"])
        #expect(viewModel.suggestedPlan?.aiSummary.contains("Recipes from Spoonacular") == true)
    }

    @Test func withoutRecipesThePlanStaysAndTheReasonIsShown() async {
        saveSetup()
        let planner = StubPlanner(result: .success(Fixtures.plan()))
        let viewModel = PlanningViewModel(
            ai: planner, defaults: storage.defaults, loadCatalog: { .init(offers: []) },
            discoverRecipes: { _ in DiscoveredRecipes(recipes: [], note: RecipeDiscovery.offlineNote) }
        )

        await viewModel.generatePlan()

        #expect(viewModel.lastError == RecipeDiscovery.offlineNote)
        #expect(planner.calls.isEmpty, "nothing to plan with")
    }
}
