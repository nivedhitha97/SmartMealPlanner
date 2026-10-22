//
//  AIPlanningService.swift
//  SmartMealPlanner
//

import Foundation

/// Abstraction for AI-assisted planning. Swap `LocalHeuristicAIPlanner` for a client that calls
/// OpenAI, Apple Foundation Models, or your backend — inputs and outputs stay the same.
protocol AIPlanningService: Sendable {
    func generateWeeklySuggestions(
        preferences: UserPreferences,
        routine: MealRoutine,
        recipes: [Recipe],
        weeklyOffers: [SupermarketOffer],
        ingredientPrices: [IngredientPrice]
    ) async throws -> AISuggestedWeekPlan
}

extension AIPlanningService {
    /// Plans with catalog prices only (no live ingredient prices).
    func generateWeeklySuggestions(
        preferences: UserPreferences,
        routine: MealRoutine,
        recipes: [Recipe],
        weeklyOffers: [SupermarketOffer]
    ) async throws -> AISuggestedWeekPlan {
        try await generateWeeklySuggestions(
            preferences: preferences, routine: routine, recipes: recipes,
            weeklyOffers: weeklyOffers, ingredientPrices: []
        )
    }
}

/// On-device heuristic that scores regional offers and builds a coherent grocery list, pricing each
/// ingredient from a matching offer, then live supermarket prices, then the recipe catalog.
/// Suitable as a fallback and for previews; replace with a remote model for richer reasoning.
final class LocalHeuristicAIPlanner: AIPlanningService, @unchecked Sendable {

    private let mealPlanner = MealPlanner()

    func generateWeeklySuggestions(
        preferences: UserPreferences,
        routine: MealRoutine,
        recipes: [Recipe],
        weeklyOffers: [SupermarketOffer],
        ingredientPrices: [IngredientPrice]
    ) async throws -> AISuggestedWeekPlan {
        let regionKey = preferences.shoppingRegion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedOffers: [SupermarketOffer]
        if regionKey.isEmpty {
            scopedOffers = weeklyOffers
        } else {
            scopedOffers = weeklyOffers.filter {
                $0.regionId == SupermarketOffer.nationalRegionId
                    || $0.regionId.localizedCaseInsensitiveContains(regionKey)
                    || regionKey.localizedCaseInsensitiveContains($0.regionId)
            }
        }

        // Only offers from supermarkets within 2 km of the postcode, when those are known.
        let localOffers = OffersList.nearby(scopedOffers, chains: preferences.nearbyChains)

        let firstPlan = mealPlanner.generateWeeklyMealPlan(
            recipes: recipes,
            preferences: preferences,
            routine: routine
        )
        func pricedLines(for plan: WeeklyMealPlan) -> [GroceryLineItem] {
            groceryLines(for: plan, people: preferences.people, offers: localOffers, ingredientPrices: ingredientPrices,
                         recipes: recipes)
        }
        // Over budget: swap dishes for cheaper ones that still fit every preference.
        let (weeklyMealPlan, swaps) = mealPlanner.fitToBudget(
            firstPlan, recipes: recipes, preferences: preferences, routine: routine,
            cost: { pricedLines(for: $0).map(\.estimatedLinePrice).reduce(0, +) },
            recipeCost: { recipeCost($0, people: preferences.people, ingredientPrices: ingredientPrices) }
        )
        let lines = pricedLines(for: weeklyMealPlan)

        let total = lines.map(\.estimatedLinePrice).reduce(0, +)
        var summary = makeSummary(
            preferences: preferences,
            weeklyMealPlan: weeklyMealPlan,
            unplannedMeals: MealPlanner.unplannedMeals(in: weeklyMealPlan, routine: routine, preferences: preferences),
            offerCount: localOffers.count,
            livePriceCount: lines.filter { line in
                line.matchedOffer == nil
                    && ingredientPrices.contains { $0.ingredientName.caseInsensitiveCompare(line.ingredientName) == .orderedSame }
            }.count,
            estimatedTotal: total
        )
        if let note = Self.budgetNote(total: total, budget: preferences.budgetWeekly, swaps: swaps) {
            summary += " " + note
        }
        let highlights = localOffers
            .sorted { ($0.savings ?? 0) > ($1.savings ?? 0) }
            .prefix(6)
            .map { offer in
                let save = offer.savings.map { String(format: "save €%.2f", $0) } ?? "promo"
                return "\(offer.storeName): \(offer.productName) — €\(String(format: "%.2f", offer.offerPrice)) (\(save))"
            }

        return AISuggestedWeekPlan(
            id: UUID(),
            createdAt: Date(),
            weeklyMealPlan: weeklyMealPlan,
            groceryLines: lines,
            aiSummary: summary,
            offerHighlights: highlights,
            estimatedGroceryTotal: total,
            budgetWeekly: preferences.budgetWeekly
        )
    }

    /// What the planner did about the budget, for the planner notes; nil when nothing needed saying.
    static func budgetNote(total: Double, budget: Double, swaps: Int) -> String? {
        let euros = { (value: Double) in String(format: "€%.2f", value) }
        if total > budget {
            return "Even with the cheapest dishes for your preferences, the week is \(euros(total - budget)) over your "
                + "\(euros(budget)) budget: raise the budget, add cuisines, or set some meals to Outside."
        }
        guard swaps > 0 else { return nil }
        return "Swapped \(swaps) \(swaps == 1 ? "dish" : "dishes") for cheaper ones to stay within your \(euros(budget)) budget."
    }

    /// The week's groceries: every ingredient's grams for the household, priced from a matching offer, else the live
    /// price, else the recipe's own price.
    func groceryLines(
        for plan: WeeklyMealPlan,
        people: Int,
        offers localOffers: [SupermarketOffer],
        ingredientPrices: [IngredientPrice],
        recipes: [Recipe]
    ) -> [GroceryLineItem] {
        var gramsByIngredient: [String: Double] = [:]
        for recipe in plan.allPlannedRecipes {
            for row in recipe.ingredients {
                let name = row.ingredient.name
                gramsByIngredient[name, default: 0] += recipe.quantity(of: row, forPeople: people)
            }
        }

        return gramsByIngredient.keys.sorted().map { name in
            let grams = gramsByIngredient[name] ?? 0
            let offer = bestOffer(forIngredientName: name, in: localOffers)
            let livePrice = ingredientPrices.first { $0.ingredientName.caseInsensitiveCompare(name) == .orderedSame }
            let price = linePrice(ingredientName: name, grams: grams, offer: offer, livePrice: livePrice, recipes: recipes)
            let rationale: String
            if let offer {
                rationale = "Matched weekly offer at \(offer.storeName) (\(offer.unitLabel))."
            } else if let livePrice {
                rationale = "Live price: about \(String(format: "€%.2f", livePrice.pricePer100g)) per 100 g across "
                    + "\(livePrice.storeCount) stores. Cheapest: \(livePrice.cheapestProduct) at \(livePrice.cheapestStore) "
                    + "(\(String(format: "€%.2f", livePrice.cheapestPrice)))."
            } else {
                rationale = "Estimated from catalog prices (no matching offer this week)."
            }
            return GroceryLineItem(
                ingredientName: name,
                totalGrams: grams,
                matchedOffer: offer,
                estimatedLinePrice: price,
                rationale: rationale
            )
        }
    }

    /// One recipe's groceries for the household at live or recipe prices (offers depend on the whole week), to rank
    /// cheaper swaps.
    func recipeCost(_ recipe: Recipe, people: Int, ingredientPrices: [IngredientPrice]) -> Double {
        recipe.ingredients.reduce(0) { sum, row in
            let name = row.ingredient.name
            let per100g = ingredientPrices.first { $0.ingredientName.caseInsensitiveCompare(name) == .orderedSame }?
                .pricePer100g ?? row.ingredient.defaultPrice
            return sum + per100g * recipe.quantity(of: row, forPeople: people) / 100
        }
    }

    func bestOffer(forIngredientName name: String, in offers: [SupermarketOffer]) -> SupermarketOffer? {
        guard !offers.isEmpty else { return nil }
        // Live feed offers say which ingredient they are; take the cheapest of those.
        let tagged = offers.filter { $0.ingredientName?.caseInsensitiveCompare(name) == .orderedSame }
        if let cheapest = tagged.min(by: { $0.offerPrice < $1.offerPrice }) {
            return cheapest
        }
        let lowered = name.lowercased()
        let scored: [(SupermarketOffer, Int)] = offers.map { offer in
            let product = offer.productName.lowercased()
            var score = 0
            if product.contains(lowered) { score += 100 }
            for part in lowered.split(separator: " ") where part.count > 2 {
                if product.contains(String(part)) { score += 40 }
            }
            if offer.category.lowercased().contains(lowered) { score += 20 }
            return (offer, score)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        return best.1 > 0 ? best.0 : nil
    }

    private func linePrice(
        ingredientName: String,
        grams: Double,
        offer: SupermarketOffer?,
        livePrice: IngredientPrice?,
        recipes: [Recipe]
    ) -> Double {
        if let offer {
            return offer.offerPrice
        }
        if let livePrice {
            return livePrice.pricePer100g * (grams / 100.0)
        }
        if let ing = firstIngredient(named: ingredientName, in: recipes) {
            return ing.defaultPrice * (grams / 100.0)
        }
        return 0
    }

    private func firstIngredient(named name: String, in recipes: [Recipe]) -> Ingredient? {
        let target = name.lowercased()
        for recipe in recipes {
            for row in recipe.ingredients where row.ingredient.name.lowercased() == target {
                return row.ingredient
            }
        }
        return nil
    }

    private func makeSummary(
        preferences: UserPreferences,
        weeklyMealPlan: WeeklyMealPlan,
        unplannedMeals: Int,
        offerCount: Int,
        livePriceCount: Int,
        estimatedTotal: Double
    ) -> String {
        let uniqueNames = Set(weeklyMealPlan.allPlannedRecipes.map(\.name))
        let mealText = uniqueNames.isEmpty
            ? "Several slots are eat-out or no recipe matched filters."
            : uniqueNames.sorted().joined(separator: ", ")
        let region = preferences.shoppingRegion.isEmpty
            ? "your area"
            : preferences.shoppingRegion
        let budget = String(format: "%.0f", preferences.budgetWeekly)
        let total = String(format: "%.2f", estimatedTotal)
        let homeMeals = weeklyMealPlan.allPlannedRecipes.count
        let breakfastNote: String
        switch preferences.breakfastRecipePreference {
        case .granolaMuesliOnly:
            breakfastNote = " Breakfast uses your granola/muesli choice (no catalog recipe)."
        case .includeRecipes:
            breakfastNote = ""
        }
        // No dish is planned twice a day or more than MealPlanner.maxTimesPerWeek times a week.
        let varietyNote = unplannedMeals > 0
            ? " \(unplannedMeals) meals are left open so no dish repeats more than \(MealPlanner.maxTimesPerWeek)× a week; add cuisines for more choice."
            : ""
        let priceNote = livePriceCount > 0
            ? " (\(livePriceCount) ingredients priced from today's supermarket prices)"
            : ""
        return """
        Analyzed \(offerCount) regional offers for \(region). Full-week plan: \(homeMeals) home-cooked meals across 7 days \
        (\(uniqueNames.count) different recipes). Highlights: \(mealText).\(breakfastNote)\(varietyNote) \
        Estimated grocery spend for aggregated ingredients is €\(total) vs. weekly target €\(budget)\(priceNote). \
        Open each day below for full recipes, photos, and video or cookbook links.
        """
    }
}
