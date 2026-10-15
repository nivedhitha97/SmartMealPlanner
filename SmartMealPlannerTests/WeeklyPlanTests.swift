//
//  WeeklyPlanTests.swift
//  SmartMealPlannerTests
//
//  Display rules for the Weekly plan screen: budget card, day picker and meal slots.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Weekly plan screen")
struct WeeklyPlanTests {

    // MARK: - Budget card

    @Test func underBudgetShowsWithinBudgetAndAmountLeft() {
        let budget = BudgetSummary(estimatedTotal: 46.80, budget: 60)

        #expect(budget.isWithinBudget)
        #expect(budget.statusText == "Within budget")
        #expect(abs(budget.progress - 0.78) < 0.0001)
        #expect(abs(budget.remaining - 13.20) < 0.0001)
        #expect(budget.remainingText == "\(13.20.euros) left to spend this week")
    }

    @Test func overBudgetShowsOverBudgetAndFullBar() {
        let budget = BudgetSummary(estimatedTotal: 78.76, budget: 50)

        #expect(!budget.isWithinBudget)
        #expect(budget.statusText == "Over budget")
        #expect(budget.progress == 1, "The bar is capped at full")
        #expect(budget.remainingText == "\(28.76.euros) over your weekly budget")
    }

    @Test func spendingExactlyTheBudgetCountsAsWithinBudget() {
        let budget = BudgetSummary(estimatedTotal: 50, budget: 50)

        #expect(budget.isWithinBudget)
        #expect(budget.progress == 1)
        #expect(budget.remainingText == "\(0.0.euros) left to spend this week")
    }

    @Test func zeroBudgetShowsAFullBarInsteadOfDividingByZero() {
        let budget = BudgetSummary(estimatedTotal: 10, budget: 0)

        #expect(budget.progress == 1)
        #expect(!budget.isWithinBudget)
    }

    @Test func budgetSummaryReadsTotalsFromThePlan() {
        let budget = BudgetSummary(plan: Fixtures.plan(total: 33.5, budget: 80))

        #expect(budget == BudgetSummary(estimatedTotal: 33.5, budget: 80))
    }

    // MARK: - Day picker

    @Test func dayPickerOpensOnTodayWhenItIsInThePlan() {
        let days = (-1...5).map { Fixtures.day(Fixtures.date(daysFromNow: $0)) }
        let weekly = WeeklyMealPlan(id: UUID(), weekStart: days[0].date, days: days)

        let index = WeeklyPlanContent.initialDayIndex(in: weekly, now: Fixtures.now, calendar: Fixtures.calendar)

        #expect(index == 1)
    }

    @Test func dayPickerOpensOnTheFirstDayWhenTodayIsNotInThePlan() {
        let days = (3...9).map { Fixtures.day(Fixtures.date(daysFromNow: $0)) }
        let weekly = WeeklyMealPlan(id: UUID(), weekStart: days[0].date, days: days)

        #expect(WeeklyPlanContent.initialDayIndex(in: weekly, now: Fixtures.now, calendar: Fixtures.calendar) == 0)
        #expect(WeeklyPlanContent.initialDayIndex(in: nil, now: Fixtures.now, calendar: Fixtures.calendar) == 0)
    }

    // MARK: - Meal slots

    @Test func homeMealCountUsesSingularAndPlural() {
        let pasta = Fixtures.recipe("Pasta")

        #expect(WeeklyPlanContent.homeMealsText(for: Fixtures.day(Fixtures.now, breakfast: pasta, lunch: pasta, dinner: pasta)) == "3 home meals")
        #expect(WeeklyPlanContent.homeMealsText(for: Fixtures.day(Fixtures.now, dinner: pasta)) == "1 home meal")
        #expect(WeeklyPlanContent.homeMealsText(for: Fixtures.day(Fixtures.now)) == "0 home meals")
    }

    @Test func emptyBreakfastWithGranolaPreferenceShowsGranola() {
        #expect(WeeklyPlanContent.emptySlotTitle(slot: .breakfast, breakfastPreference: .granolaMuesliOnly) == "Granola / muesli")
        #expect(WeeklyPlanContent.emptySlotDetail(slot: .breakfast, breakfastPreference: .granolaMuesliOnly) == "Buy granola or muesli separately")
    }

    @Test(arguments: [
        (MealSlot.breakfast, BreakfastRecipePreference.includeRecipes),
        (.lunch, .granolaMuesliOnly),
        (.dinner, .includeRecipes),
    ])
    func otherEmptySlotsShowOutsideOrFlexible(slot: MealSlot, preference: BreakfastRecipePreference) {
        #expect(WeeklyPlanContent.emptySlotTitle(slot: slot, breakfastPreference: preference) == "Outside / flexible")
        #expect(WeeklyPlanContent.emptySlotDetail(slot: slot, breakfastPreference: preference) == "No recipe needed")
    }
}
