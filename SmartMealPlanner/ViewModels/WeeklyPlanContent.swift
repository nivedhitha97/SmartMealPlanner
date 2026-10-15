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

    static let groceryPreviewCount = 5

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
    static func emptySlotTitle(slot: MealSlot, breakfastPreference: BreakfastRecipePreference) -> String {
        isGranolaSlot(slot, breakfastPreference) ? "Granola / muesli" : "Outside / flexible"
    }

    /// Detail line for a slot that has no recipe.
    static func emptySlotDetail(slot: MealSlot, breakfastPreference: BreakfastRecipePreference) -> String {
        isGranolaSlot(slot, breakfastPreference) ? "Buy granola or muesli separately" : "No recipe needed"
    }

    static func isGranolaSlot(_ slot: MealSlot, _ breakfastPreference: BreakfastRecipePreference) -> Bool {
        slot == .breakfast && breakfastPreference == .granolaMuesliOnly
    }

    /// Grocery rows to show: the first few unless the list is expanded.
    static func visibleGroceryLines(_ lines: [GroceryLineItem], showAll: Bool) -> [GroceryLineItem] {
        showAll ? lines : Array(lines.prefix(groceryPreviewCount))
    }

    /// Whether to offer "Show all N items".
    static func canExpandGroceries(_ lines: [GroceryLineItem]) -> Bool {
        lines.count > groceryPreviewCount
    }
}

/// Which grocery lines have been ticked off. Not persisted.
struct GroceryChecklist: Equatable {
    private(set) var checked: Set<UUID> = []

    func isChecked(_ line: GroceryLineItem) -> Bool {
        checked.contains(line.id)
    }

    mutating func toggle(_ line: GroceryLineItem) {
        if checked.contains(line.id) {
            checked.remove(line.id)
        } else {
            checked.insert(line.id)
        }
    }

    mutating func reset() {
        checked = []
    }
}
