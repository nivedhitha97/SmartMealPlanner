//
//  PlanGenerationTests.swift
//  SmartMealPlannerTests
//
//  The planning engine behind the Weekly plan screen: recipe filtering, meal selection,
//  grocery aggregation, offer matching and nutrition totals.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Plan generation")
struct PlanGenerationTests {

    private let chicken = Fixtures.ingredient("Chicken Breast", calories: 165, price: 1.2)
    private let tomato = Fixtures.ingredient("Tomato", calories: 20, price: 0.4)
    private let feta = Fixtures.ingredient("Feta Cheese", calories: 260, price: 1.5)
    private let lentils = Fixtures.ingredient("Red Lentils", calories: 350, price: 0.3)
    private let peanutButter = Fixtures.ingredient("Peanut Butter", calories: 600, price: 0.9)

    private var chickenBowl: Recipe { Fixtures.recipe("Chicken Bowl", cuisine: "Asian", ingredients: [(chicken, 150), (tomato, 50)]) }
    private var greekSalad: Recipe { Fixtures.recipe("Greek Salad", cuisine: "Greek", ingredients: [(tomato, 150), (feta, 60)]) }
    private var lentilDal: Recipe { Fixtures.recipe("Lentil Dal", cuisine: "Indian", ingredients: [(lentils, 100), (tomato, 100)]) }
    private var satay: Recipe { Fixtures.recipe("Satay", cuisine: "Asian", ingredients: [(peanutButter, 30), (tomato, 50)]) }

    private let allFixed = MealRoutine(breakfastType: .fixed, lunchType: .fixed, dinnerType: .fixed)
    private let lunchOnly = MealRoutine(breakfastType: .outside, lunchType: .fixed, dinnerType: .outside)

    private func weekPlan(_ recipes: [Recipe], _ preferences: UserPreferences, routine: MealRoutine? = nil) -> WeeklyMealPlan {
        MealPlanner().generateWeeklyMealPlan(
            recipes: recipes,
            preferences: preferences,
            routine: routine ?? allFixed,
            startingFrom: Fixtures.now,
            calendar: Fixtures.calendar
        )
    }

    private func plannedNames(_ plan: WeeklyMealPlan) -> Set<String> {
        Set(plan.allPlannedRecipes.map(\.name))
    }

    // MARK: - Week structure

    @Test func planCoversSevenConsecutiveDaysFromTheStartOfToday() {
        let plan = weekPlan([greekSalad], Fixtures.preferences())

        let startOfToday = Fixtures.calendar.startOfDay(for: Fixtures.now)
        #expect(plan.weekStart == startOfToday)
        #expect(plan.days.map(\.date) == (0..<7).map { Fixtures.calendar.date(byAdding: .day, value: $0, to: startOfToday)! })
    }

    // MARK: - Filtering

    @Test func vegetarianPlanSkipsMeat() {
        let plan = weekPlan([chickenBowl, greekSalad], Fixtures.preferences(diet: "Vegetarian"))

        #expect(plannedNames(plan) == ["Greek Salad"])
    }

    @Test func veganPlanSkipsMeatAndDairy() {
        let plan = weekPlan([chickenBowl, greekSalad, lentilDal], Fixtures.preferences(diet: "Vegan"))

        #expect(plannedNames(plan) == ["Lentil Dal"])
    }

    @Test func allergiesAndDislikesRemoveRecipesContainingThatIngredient() {
        let allergic = weekPlan([satay, lentilDal], Fixtures.preferences(allergies: ["peanut"]))
        let dislikesFeta = weekPlan([greekSalad, lentilDal], Fixtures.preferences(dislikes: [" FETA "]))

        #expect(plannedNames(allergic) == ["Lentil Dal"])
        #expect(plannedNames(dislikesFeta) == ["Lentil Dal"])
    }

    @Test func cuisineChoiceIsMatchedCaseInsensitively() {
        // Fixed meals take the first matching recipe, so the Asian bowl listed first must be filtered out.
        let greek = weekPlan([chickenBowl, greekSalad, lentilDal], Fixtures.preferences(cuisines: ["GREEK"]))
        let indian = weekPlan([chickenBowl, greekSalad, lentilDal], Fixtures.preferences(cuisines: ["indian"]))

        #expect(plannedNames(greek) == ["Greek Salad"])
        #expect(plannedNames(indian) == ["Lentil Dal"])
    }

    @Test func noMatchingRecipesLeavesEverySlotEmpty() {
        let plan = weekPlan([chickenBowl], Fixtures.preferences(diet: "Vegetarian"))

        #expect(plan.allPlannedRecipes.isEmpty)
        #expect(plan.days.count == 7)
    }

    // MARK: - Meal selection

    @Test func fixedMealsUseTheFirstMatchingRecipeEveryDay() {
        let plan = weekPlan([greekSalad, lentilDal], Fixtures.preferences())

        for day in plan.days {
            #expect(day.breakfast?.name == "Greek Salad")
            #expect(day.lunch?.name == "Greek Salad")
            #expect(day.dinner?.name == "Greek Salad")
        }
    }

    @Test func outsideMealsGetNoRecipe() {
        let plan = weekPlan([greekSalad], Fixtures.preferences(), routine: lunchOnly)

        #expect(plan.days.allSatisfy { $0.breakfast == nil && $0.dinner == nil })
        #expect(plan.days.allSatisfy { $0.lunch?.name == "Greek Salad" })
    }

    @Test func granolaPreferenceLeavesBreakfastEmptyButPlansOtherMeals() {
        let plan = weekPlan([greekSalad], Fixtures.preferences(breakfast: .granolaMuesliOnly))

        #expect(plan.days.allSatisfy { $0.breakfast == nil })
        #expect(plan.days.allSatisfy { $0.lunch != nil && $0.dinner != nil })
    }

    @Test(arguments: [MealType.homeCooked, .flexible])
    func homeCookedAndFlexibleMealsPickFromMatchingRecipes(type: MealType) {
        let routine = MealRoutine(breakfastType: .outside, lunchType: type, dinnerType: type)
        let plan = weekPlan([chickenBowl, greekSalad, lentilDal], Fixtures.preferences(diet: "Vegetarian"), routine: routine)

        #expect(plan.allPlannedRecipes.count == 14)
        #expect(plannedNames(plan).isSubset(of: ["Greek Salad", "Lentil Dal"]))
    }

    // MARK: - Grocery list and offers

    @Test func groceryListAddsUpIngredientsAcrossTheWeek() async throws {
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: []
        )

        let lines = Dictionary(uniqueKeysWithValues: plan.groceryLines.map { ($0.ingredientName, $0) })
        #expect(plan.groceryLines.map(\.ingredientName) == ["Feta Cheese", "Tomato"], "Sorted by name")
        #expect(lines["Tomato"]?.totalGrams == 1050, "150 g × 7 lunches")
        #expect(lines["Feta Cheese"]?.totalGrams == 420, "60 g × 7 lunches")
    }

    @Test func unmatchedIngredientsArePricedFromTheCatalog() async throws {
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: []
        )

        let tomatoLine = try #require(plan.groceryLines.first { $0.ingredientName == "Tomato" })
        #expect(tomatoLine.matchedOffer == nil)
        #expect(abs(tomatoLine.estimatedLinePrice - 0.4 * (1050 / 100)) < 0.0001)
        #expect(abs(plan.estimatedGroceryTotal - plan.groceryLines.map(\.estimatedLinePrice).reduce(0, +)) < 0.0001)
    }

    @Test func matchingOfferInYourRegionSetsThePrice() async throws {
        let offer = Fixtures.offer(product: "Cherry Tomato 250g", price: 1.19, regularPrice: 1.79, region: "NL-North")

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(region: "Amsterdam, NL-North"),
            routine: lunchOnly, recipes: [greekSalad], weeklyOffers: [offer]
        )

        let tomatoLine = try #require(plan.groceryLines.first { $0.ingredientName == "Tomato" })
        #expect(tomatoLine.matchedOffer?.id == offer.id)
        #expect(tomatoLine.estimatedLinePrice == 1.19)
        #expect(plan.offerHighlights.count == 1)
    }

    @Test func offersFromOtherRegionsAreIgnored() async throws {
        let amsterdamOnly = Fixtures.offer(product: "Cherry Tomato 250g", price: 1.19, region: "Amsterdam")

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(region: "Utrecht, NL-West"),
            routine: lunchOnly, recipes: [greekSalad], weeklyOffers: [amsterdamOnly]
        )

        #expect(plan.groceryLines.allSatisfy { $0.matchedOffer == nil })
        #expect(plan.offerHighlights.isEmpty)
    }

    @Test func offerHighlightsListTheBiggestSavingsFirstUpToSix() async throws {
        let offers = (1...8).map { i in
            Fixtures.offer(product: "Deal \(i)", price: 1, regularPrice: 1 + Double(i))
        }

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: offers
        )

        #expect(plan.offerHighlights.count == 6)
        #expect(plan.offerHighlights.first?.contains("Deal 8") == true)
    }

    @Test func planCarriesTheBudgetForTheBudgetCard() async throws {
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(budget: 85), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: []
        )

        #expect(plan.budgetWeekly == 85)
        #expect(plan.isWithinBudget == (plan.estimatedGroceryTotal <= 85))
    }

    // MARK: - Nutrition

    @Test func nutritionTotalsScaleIngredientsPer100Grams() {
        let totals = NutritionTotals.aggregate(recipes: [greekSalad, lentilDal])

        // Greek salad: tomato 150 g (20 kcal) + feta 60 g (260 kcal); dal: lentils 100 g (350) + tomato 100 g (20).
        let saladCalories: Double = 1.5 * 20 + 0.6 * 260
        let dalCalories: Double = 1.0 * 350 + 1.0 * 20
        // Every fixture ingredient has 10 g protein per 100 g; 410 g of ingredients in total.
        let expectedProtein: Double = 4.1 * 10
        #expect(abs(totals.calories - (saladCalories + dalCalories)) < 0.0001)
        #expect(abs(totals.protein - expectedProtein) < 0.0001)
        #expect(NutritionTotals.aggregate(recipes: []).calories == 0)
    }
}
