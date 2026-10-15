//
//  TestFixtures.swift
//  SmartMealPlannerTests
//
//  Small builders for model values used across the test suites.
//

import Foundation
@testable import SmartMealPlanner

@MainActor
enum Fixtures {

    /// Fixed calendar and dates so date-based tests don't depend on the device's time zone or clock.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Thursday 8 October 2026, 12:00 UTC.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!

    static func date(daysFromNow days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    static func ingredient(
        _ name: String,
        calories: Double = 100,
        protein: Double = 10,
        carbs: Double = 10,
        fat: Double = 5,
        price: Double = 1
    ) -> Ingredient {
        Ingredient(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat, defaultPrice: price)
    }

    static func recipe(
        _ name: String,
        cuisine: String = "Italian",
        ingredients: [(Ingredient, Double)] = [],
        imageURL: String? = nil,
        youtubeURL: String? = nil,
        cookbookURL: String? = nil
    ) -> Recipe {
        Recipe(
            id: UUID(),
            name: name,
            cuisine: cuisine,
            ingredients: ingredients.map { RecipeIngredient(ingredient: $0.0, quantity: $0.1) },
            instructions: ["Cook", "Serve"],
            imageURL: imageURL,
            youtubeURL: youtubeURL,
            cookbookURL: cookbookURL
        )
    }

    static func offer(
        store: String = "Albert Heijn",
        product: String,
        category: String = "Produce",
        price: Double,
        regularPrice: Double? = nil,
        validUntil: Date? = nil,
        region: String = "NL-North"
    ) -> SupermarketOffer {
        SupermarketOffer(
            id: UUID(),
            storeName: store,
            productName: product,
            category: category,
            offerPrice: price,
            regularPrice: regularPrice,
            unitLabel: "pack",
            validUntil: validUntil ?? date(daysFromNow: 7),
            regionId: region,
            notes: nil
        )
    }

    static func ingredientPrice(_ name: String, per100g: Double, store: String = "Lidl") -> IngredientPrice {
        IngredientPrice(
            ingredientName: name,
            pricePer100g: per100g,
            cheapestStore: store,
            cheapestProduct: "\(name) 500 g",
            cheapestPrice: per100g * 4,
            cheapestSize: "500 g",
            cheapestPricePer100g: per100g * 0.8,
            storeCount: 6,
            productCount: 20
        )
    }

    static func preferences(
        diet: String = "Non-Vegetarian",
        cuisines: [String] = [],
        dislikes: [String] = [],
        allergies: [String] = [],
        budget: Double = 50,
        region: String = "",
        breakfast: BreakfastRecipePreference = .includeRecipes
    ) -> UserPreferences {
        UserPreferences(
            dietType: diet,
            cuisines: cuisines,
            dislikes: dislikes,
            allergies: allergies,
            budgetWeekly: budget,
            shoppingRegion: region,
            breakfastRecipePreference: breakfast
        )
    }

    static func groceryLine(_ name: String, price: Double = 1) -> GroceryLineItem {
        GroceryLineItem(ingredientName: name, totalGrams: 100, matchedOffer: nil, estimatedLinePrice: price, rationale: "")
    }

    static func day(_ date: Date, breakfast: Recipe? = nil, lunch: Recipe? = nil, dinner: Recipe? = nil) -> DailyMealPlanSlot {
        DailyMealPlanSlot(date: date, breakfast: breakfast, lunch: lunch, dinner: dinner)
    }

    static func plan(total: Double = 40, budget: Double = 50, days: [DailyMealPlanSlot] = []) -> AISuggestedWeekPlan {
        AISuggestedWeekPlan(
            id: UUID(),
            createdAt: now,
            weeklyMealPlan: WeeklyMealPlan(id: UUID(), weekStart: days.first?.date ?? now, days: days),
            groceryLines: [],
            aiSummary: "Summary",
            offerHighlights: [],
            estimatedGroceryTotal: total,
            budgetWeekly: budget
        )
    }
}

/// A throwaway UserDefaults suite, removed when the test that owns it finishes.
final class IsolatedDefaults {
    private let suiteName = "SmartMealPlannerTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}
