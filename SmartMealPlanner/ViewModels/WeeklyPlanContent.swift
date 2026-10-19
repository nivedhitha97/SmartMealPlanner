//
//  WeeklyPlanContent.swift
//  SmartMealPlanner
//
//  Display rules for the Weekly plan screen, kept free of SwiftUI so they can be unit tested.
//

import Foundation

/// Numbers and copy for the budget card.
struct BudgetSummary: Equatable {
    let estimatedTotal: Double
    let budget: Double

    init(estimatedTotal: Double, budget: Double) {
        self.estimatedTotal = estimatedTotal
        self.budget = budget
    }

    init(plan: AISuggestedWeekPlan) {
        self.init(estimatedTotal: plan.estimatedGroceryTotal, budget: plan.budgetWeekly)
    }

    var isWithinBudget: Bool { estimatedTotal <= budget }

    /// How full the progress bar is, from 0 to 1. Full when there is no budget.
    var progress: Double {
        guard budget > 0 else { return 1 }
        return min(max(estimatedTotal / budget, 0), 1)
    }

    /// Negative when over budget.
    var remaining: Double { budget - estimatedTotal }

    var statusText: String { isWithinBudget ? "Within budget" : "Over budget" }

    var remainingText: String {
        remaining >= 0
            ? "\(remaining.euros) left to spend this week"
            : "\((-remaining).euros) over your weekly budget"
    }
}

enum WeeklyPlanContent {

    /// The day the day picker opens on: today if it's in the plan, otherwise the first day.
    static func initialDayIndex(in weekly: WeeklyMealPlan?, now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let weekly else { return 0 }
        return weekly.days.firstIndex { calendar.isDate($0.date, inSameDayAs: now) } ?? 0
    }

    /// "3 home meals" / "1 home meal" / "0 home meals"
    static func homeMealsText(for day: DailyMealPlanSlot) -> String {
        let count = day.mealsWithSlot.compactMap(\.1).count
        return "\(count) home \(count == 1 ? "meal" : "meals")"
    }

    /// Title for a slot that has no recipe.
    static func emptySlotTitle(slot: MealSlot, breakfastPreference: BreakfastRecipePreference,
                               mealType: MealType? = nil) -> String {
        if isGranolaSlot(slot, breakfastPreference) { return "Granola / muesli" }
        return wantsRecipe(mealType) ? "No recipe left" : "Outside / flexible"
    }

    /// Detail line for a slot that has no recipe.
    static func emptySlotDetail(slot: MealSlot, breakfastPreference: BreakfastRecipePreference,
                                mealType: MealType? = nil) -> String {
        if isGranolaSlot(slot, breakfastPreference) { return "Buy granola or muesli separately" }
        return wantsRecipe(mealType)
            ? "Matching dishes are already planned \(MealPlanner.maxTimesPerWeek)× this week. Add cuisines for more variety."
            : "No recipe needed"
    }

    /// The routine's meal type for a slot.
    static func mealType(for slot: MealSlot, in routine: MealRoutine?) -> MealType? {
        guard let routine else { return nil }
        switch slot {
        case .breakfast: return routine.breakfastType
        case .lunch: return routine.lunchType
        case .dinner: return routine.dinnerType
        }
    }

    /// Whether the routine wanted a recipe for this slot (so an empty slot means none was left).
    private static func wantsRecipe(_ mealType: MealType?) -> Bool {
        guard let mealType else { return false }
        return mealType != .outside
    }

    static func isGranolaSlot(_ slot: MealSlot, _ breakfastPreference: BreakfastRecipePreference) -> Bool {
        slot == .breakfast && breakfastPreference == .granolaMuesliOnly
    }
}
