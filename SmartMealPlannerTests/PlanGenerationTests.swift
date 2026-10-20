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

    /// Twelve distinct dishes: enough for 21 meals at no more than twice a week each, even when Fixed uses them
    /// strictly in order (each dish fills two days, three a day).
    private var manyDishes: [Recipe] {
        (1...12).map { Fixtures.recipe("Dish \($0)", cuisine: "Greek", ingredients: [(tomato, 100)]) }
    }

    private func expectVarietyRules(_ plan: WeeklyMealPlan, sourceLocation: SourceLocation = #_sourceLocation) {
        for day in plan.days {
            let names = [day.breakfast, day.lunch, day.dinner].compactMap { $0?.name }
            #expect(Set(names).count == names.count, "no dish twice on \(day.date)", sourceLocation: sourceLocation)
        }
        let counts = Dictionary(plan.allPlannedRecipes.map { ($0.name, 1) }, uniquingKeysWith: +)
        #expect(counts.values.allSatisfy { $0 <= MealPlanner.maxTimesPerWeek }, "at most twice a week: \(counts)",
                sourceLocation: sourceLocation)
    }

    @Test(arguments: [MealType.fixed, .homeCooked, .flexible])
    func noDishIsRepeatedOnADayOrMoreThanTwiceAWeek(type: MealType) {
        let routine = MealRoutine(breakfastType: type, lunchType: type, dinnerType: type)
        let plan = weekPlan(manyDishes, Fixtures.preferences(), routine: routine)

        #expect(plan.allPlannedRecipes.count == 21, "twelve dishes are enough to fill every meal")
        expectVarietyRules(plan)
    }

    @Test func fixedMealsKeepTheFirstChoiceAsLongAsTheLimitAllows() {
        let plan = weekPlan([greekSalad, lentilDal, chickenBowl], Fixtures.preferences(), routine: lunchOnly)

        #expect(plan.days.map { $0.lunch?.name } == ["Greek Salad", "Greek Salad", "Lentil Dal", "Lentil Dal",
                                                    "Chicken Bowl", "Chicken Bowl", nil])
    }

    // MARK: - Meals each dish is for

    private func tagged(_ recipe: Recipe, _ meals: [MealSlot]) -> Recipe {
        var copy = recipe
        copy.meals = meals.map(\.rawValue)
        return copy
    }

    @Test func breakfastsOnlyGetBreakfastDishesAndMainsOnlyMainDishes() {
        let porridge = tagged(Fixtures.recipe("Porridge", cuisine: "Greek", ingredients: [(tomato, 10)]), [.breakfast])
        let salad = tagged(greekSalad, [.lunch, .dinner])
        let plan = weekPlan([porridge, salad], Fixtures.preferences())

        #expect(plan.days.compactMap { $0.breakfast?.name }.allSatisfy { $0 == "Porridge" })
        #expect(plan.days.flatMap { [$0.lunch?.name, $0.dinner?.name] }.compactMap { $0 }.allSatisfy { $0 == "Greek Salad" })
        expectVarietyRules(plan)
    }

    @Test func breakfastComesFromAnotherCuisineWhenTheChosenOnesHaveNone() {
        let poha = tagged(Fixtures.recipe("Poha", cuisine: "Indian", ingredients: [(lentils, 10)]), [.breakfast])
        let porkBreakfast = tagged(Fixtures.recipe("Bacon Roll", cuisine: "Dutch",
                                                   ingredients: [(Fixtures.ingredient("Bacon", calories: 300, price: 1), 50)]),
                                   [.breakfast])
        let salad = tagged(greekSalad, [.lunch, .dinner])
        let plan = weekPlan([poha, porkBreakfast, salad], Fixtures.preferences(diet: "Vegetarian", cuisines: ["Greek"]))

        #expect(plan.days.first?.breakfast?.name == "Poha", "another cuisine, but still vegetarian")
        #expect(!plannedNames(plan).contains("Bacon Roll"))
        #expect(plan.days.compactMap(\.lunch).allSatisfy { $0.cuisine == "Greek" }, "mains keep to the chosen cuisines")
    }

    @Test(arguments: [("Champignons", false, false), ("Eggplant", false, false), ("Peanut Butter", false, false),
                      ("Coconut Milk", false, false), ("Butter Beans", false, false), ("Prawns", true, true),
                      ("Minced Beef", true, true), ("Fish Sauce", true, true), ("Smoked Sausage", true, true),
                      ("Greek Yogurt", false, true), ("Eggs", false, true), ("Gruyère Cheese", false, true)])
    func meatAndAnimalProductsAreRecognisedByWord(name: String, meat: Bool, animal: Bool) {
        let recipe = Fixtures.recipe("Dish", ingredients: [(Fixtures.ingredient(name, calories: 100, price: 1), 100)])
        #expect(recipe.containsMeat == meat)
        #expect(recipe.containsAnimalProducts == animal)
    }

    /// The UI tests' recipe set (a realistic catalog): every diet in every cuisine gets a full week.
    @Test func aRealisticCatalogFillsAWeekForEveryDietInEveryCuisine() throws {
        let recipes = try JSONLoader.load("UITestRecipes", as: [Recipe].self)
        #expect(recipes.count >= 49)
        for recipe in recipes {
            #expect(recipe.instructions.count >= 6, "\(recipe.name) has detailed steps")
            #expect(recipe.ingredients.count >= 5, "\(recipe.name) has a real ingredient list")
            #expect(recipe.meals?.isEmpty == false, "\(recipe.name) says which meals it is for")
        }
        for cuisine in PreferencesForm.cuisineOptions {
            for diet in ["Non-Vegetarian", "Vegetarian", "Vegan"] {
                let plan = weekPlan(recipes, Fixtures.preferences(diet: diet, cuisines: [cuisine]))
                #expect(plan.days.allSatisfy { $0.breakfast != nil }, "\(diet) \(cuisine): a breakfast every day")
                #expect(plan.allPlannedRecipes.count >= 11, "\(diet) \(cuisine): most of the week planned")
                expectVarietyRules(plan)
            }
        }
    }

    @Test func tooFewDishesLeaveSlotsEmptyRatherThanRepeating() {
        let plan = weekPlan([greekSalad, lentilDal], Fixtures.preferences())

        #expect(plan.allPlannedRecipes.count == 4, "two dishes × twice a week")
        expectVarietyRules(plan)
        #expect(MealPlanner.unplannedMeals(in: plan, routine: allFixed, preferences: Fixtures.preferences()) == 17)
    }

    @Test func outsideMealsGetNoRecipe() {
        let plan = weekPlan(manyDishes, Fixtures.preferences(), routine: lunchOnly)

        #expect(plan.days.allSatisfy { $0.breakfast == nil && $0.dinner == nil })
        #expect(plan.days.allSatisfy { $0.lunch != nil })
    }

    @Test func granolaPreferenceLeavesBreakfastEmptyButPlansOtherMeals() {
        let plan = weekPlan(manyDishes, Fixtures.preferences(breakfast: .granolaMuesliOnly))

        #expect(plan.days.allSatisfy { $0.breakfast == nil })
        #expect(plan.days.allSatisfy { $0.lunch != nil && $0.dinner != nil })
    }

    @Test(arguments: [MealType.homeCooked, .flexible])
    func homeCookedAndFlexibleMealsPickFromMatchingRecipes(type: MealType) {
        let routine = MealRoutine(breakfastType: .outside, lunchType: type, dinnerType: type)
        let plan = weekPlan([chickenBowl, greekSalad, lentilDal], Fixtures.preferences(diet: "Vegetarian"), routine: routine)

        #expect(plan.allPlannedRecipes.count == 4, "two vegetarian dishes, twice a week each")
        #expect(plannedNames(plan) == ["Greek Salad", "Lentil Dal"])
        expectVarietyRules(plan)
    }

    // MARK: - Grocery list and offers

    @Test func groceryListAddsUpIngredientsAcrossTheWeek() async throws {
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: []
        )

        let lines = Dictionary(uniqueKeysWithValues: plan.groceryLines.map { ($0.ingredientName, $0) })
        #expect(plan.groceryLines.map(\.ingredientName) == ["Feta Cheese", "Tomato"], "Sorted by name")
        #expect(lines["Tomato"]?.totalGrams == 300, "150 g × 2 lunches (a dish is planned at most twice a week)")
        #expect(lines["Feta Cheese"]?.totalGrams == 120, "60 g × 2 lunches")
        #expect(plan.aiSummary.contains("5 meals are left open"), "the notes say why the other lunches are empty")
    }

    @Test func groceryAmountsScaleToThePeopleInPreferences() async throws {
        var family = Fixtures.preferences()
        family.people = 3
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: family, routine: lunchOnly, recipes: [greekSalad], weeklyOffers: []
        )

        let tomato = try #require(plan.groceryLines.first { $0.ingredientName == "Tomato" })
        #expect(tomato.totalGrams == 900, "150 g × 2 lunches × 3 people")
        #expect(abs(tomato.estimatedLinePrice - 0.4 * 9) < 0.0001, "the cost scales with it")
    }

    @Test func recipeAmountsAreForItsServingsAndScaleToPeople() {
        let stew = Recipe(id: UUID(), name: "Stew", cuisine: "Dutch",
                          ingredients: [RecipeIngredient(ingredient: lentils, quantity: 400)], servings: 4)
        let row = stew.ingredients[0]

        #expect(stew.quantity(of: row, forPeople: 1) == 100)
        #expect(stew.quantity(of: row, forPeople: 6) == 600)
        #expect(abs(stew.estimatedCalories - 350) < 0.0001, "calories are per serving: 100 g × 3.5 kcal/g")
    }

    @Test func unmatchedIngredientsArePricedFromTheCatalog() async throws {
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: []
        )

        let tomatoLine = try #require(plan.groceryLines.first { $0.ingredientName == "Tomato" })
        #expect(tomatoLine.matchedOffer == nil)
        #expect(abs(tomatoLine.estimatedLinePrice - 0.4 * (300 / 100)) < 0.0001)
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

    @Test func liveIngredientPricesReplaceCatalogPrices() async throws {
        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: [],
            ingredientPrices: [Fixtures.ingredientPrice("tomato", per100g: 0.41, store: "Dirk")]
        )

        let tomatoLine = try #require(plan.groceryLines.first { $0.ingredientName == "Tomato" })
        #expect(abs(tomatoLine.estimatedLinePrice - 0.41 * (300 / 100)) < 0.0001)
        #expect(tomatoLine.rationale.hasPrefix("Live price"))
        #expect(tomatoLine.rationale.contains("Dirk"))
        let fetaLine = try #require(plan.groceryLines.first { $0.ingredientName == "Feta Cheese" })
        #expect(fetaLine.rationale.hasPrefix("Estimated from catalog"), "No live price, so the catalog price is used")
        #expect(plan.aiSummary.contains("1 ingredients priced from today's supermarket prices"))
    }

    @Test func matchingOfferBeatsTheLivePrice() async throws {
        let offer = Fixtures.offer(product: "Cherry Tomato 250g", price: 1.19, region: "NL-North")

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(region: "Amsterdam, NL-North"), routine: lunchOnly,
            recipes: [greekSalad], weeklyOffers: [offer],
            ingredientPrices: [Fixtures.ingredientPrice("Tomato", per100g: 0.41)]
        )

        let tomatoLine = try #require(plan.groceryLines.first { $0.ingredientName == "Tomato" })
        #expect(tomatoLine.matchedOffer?.id == offer.id)
        #expect(tomatoLine.estimatedLinePrice == 1.19)
    }

    @Test func nationalOffersApplyInEveryRegion() async throws {
        let national = Fixtures.offer(product: "Cherry Tomato 250g", price: 1.19, region: SupermarketOffer.nationalRegionId)

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(region: "Maastricht, NL-South"),
            routine: lunchOnly, recipes: [greekSalad], weeklyOffers: [national]
        )

        #expect(plan.groceryLines.first { $0.ingredientName == "Tomato" }?.matchedOffer?.id == national.id)
    }

    @Test func feedOffersTaggedWithAnIngredientMatchEvenWithADutchName() async throws {
        var cheap = Fixtures.offer(store: "Dirk", product: "Snoeptomaten 250 g", price: 0.99, region: "NL")
        cheap.ingredientName = "Tomato"
        var dearer = Fixtures.offer(store: "Jumbo", product: "Cherrytomaten 500 g", price: 1.79, region: "NL")
        dearer.ingredientName = "Tomato"

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: Fixtures.preferences(), routine: lunchOnly, recipes: [greekSalad], weeklyOffers: [dearer, cheap]
        )

        #expect(plan.groceryLines.first { $0.ingredientName == "Tomato" }?.matchedOffer?.id == cheap.id,
                "The cheapest tagged offer wins")
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
