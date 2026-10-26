//
//  MealPlan.swift
//  SmartMealPlanner
//

import Foundation

/// One calendar day of breakfast / lunch / dinner (recipe or outside).
struct DailyMealPlanSlot: Identifiable, Codable {
    var id: UUID
    var date: Date
    var breakfast: Recipe?
    var lunch: Recipe?
    var dinner: Recipe?
    /// Meals ("Lunch", …) left without a recipe to keep the week within the budget's 10% margin; nil when none.
    var budgetOpenSlots: [String]?

    init(
        id: UUID = UUID(),
        date: Date,
        breakfast: Recipe?,
        lunch: Recipe?,
        dinner: Recipe?
    ) {
        self.id = id
        self.date = date
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
    }

    func isOpenForBudget(_ slot: MealSlot) -> Bool {
        budgetOpenSlots?.contains(slot.rawValue) == true
    }

    var mealsWithSlot: [(MealSlot, Recipe?)] {
        [(.breakfast, breakfast), (.lunch, lunch), (.dinner, dinner)]
    }

    subscript(slot: MealSlot) -> Recipe? {
        get {
            switch slot {
            case .breakfast: return breakfast
            case .lunch: return lunch
            case .dinner: return dinner
            }
        }
        set {
            switch slot {
            case .breakfast: breakfast = newValue
            case .lunch: lunch = newValue
            case .dinner: dinner = newValue
            }
        }
    }
}

enum MealSlot: String, CaseIterable, Hashable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
}

/// Seven days of planned meals starting at `weekStart` (start of first day).
struct WeeklyMealPlan: Identifiable, Codable {
    var id: UUID
    var weekStart: Date
    var days: [DailyMealPlanSlot]

    /// Every home-cooked recipe appearing across the week (repeats if the same recipe is picked twice).
    var allPlannedRecipes: [Recipe] {
        days.flatMap { day in
            [day.breakfast, day.lunch, day.dinner].compactMap { $0 }
        }
    }
}
