//
//  MealPlanner.swift
//  SmartMealPlanner
//

import Foundation

final class MealPlanner {

    /// A dish is planned at most this many times a week (and never twice on the same day).
    static let maxTimesPerWeek = 2

    /// Builds seven consecutive days (from the start of `startingFrom`) using the same routine each day.
    /// Each slot takes dishes meant for that meal (no pasta for breakfast). A dish appears at most once a day and at
    /// most `maxTimesPerWeek` times a week; a slot is left empty when every matching recipe has reached that limit.
    /// Breakfasts may come from other cuisines when the chosen ones have none left: few cuisines have many.
    func generateWeeklyMealPlan(
        recipes: [Recipe],
        preferences: UserPreferences,
        routine: MealRoutine,
        startingFrom: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyMealPlan {
        let (filtered, otherBreakfasts) = pools(recipes, preferences)
        let weekStart = calendar.startOfDay(for: startingFrom)
        var timesThisWeek: [String: Int] = [:]
        let days: [DailyMealPlanSlot] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            var usedToday: Set<String> = []
            func pick(_ type: MealType, for slot: MealSlot) -> Recipe? {
                func allowed(_ pool: [Recipe]) -> [Recipe] {
                    pool.filter {
                        $0.suits(slot) && timesThisWeek[Self.dishKey($0), default: 0] < Self.maxTimesPerWeek
                            && !usedToday.contains(Self.dishKey($0))
                    }
                }
                var eligible = allowed(filtered)
                if eligible.isEmpty && slot == .breakfast { eligible = allowed(otherBreakfasts) }
                guard let recipe = selectMeal(type: type, from: eligible, timesThisWeek: timesThisWeek) else { return nil }
                timesThisWeek[Self.dishKey(recipe), default: 0] += 1
                usedToday.insert(Self.dishKey(recipe))
                return recipe
            }
            let breakfast = preferences.breakfastRecipePreference == .granolaMuesliOnly
                ? nil : pick(routine.breakfastType, for: .breakfast)
            let lunch = pick(routine.lunchType, for: .lunch)
            let dinner = pick(routine.dinnerType, for: .dinner)
            return DailyMealPlanSlot(date: date, breakfast: breakfast, lunch: lunch, dinner: dinner)
        }
        return WeeklyMealPlan(id: UUID(), weekStart: weekStart, days: days)
    }

    /// Recipes that fit the preferences, and breakfasts from other cuisines that fit the diet (used when the chosen
    /// cuisines have none left).
    private func pools(_ recipes: [Recipe], _ preferences: UserPreferences) -> (fitting: [Recipe], otherBreakfasts: [Recipe]) {
        let fitting = filterRecipes(recipes, preferences)
        var anyCuisine = preferences
        anyCuisine.cuisines = []
        let ids = Set(fitting.map(\.id))
        let otherBreakfasts = filterRecipes(recipes, anyCuisine).filter { recipe in
            recipe.meals?.contains(MealSlot.breakfast.rawValue) == true && !ids.contains(recipe.id)
        }
        return (fitting, otherBreakfasts)
    }

    /// How far over the budget a week may go when no cheaper dishes are left: 10%.
    static let budgetMargin = 0.10

    /// The most a week's groceries may cost: the budget plus the margin.
    static func budgetCeiling(_ budget: Double) -> Double {
        budget * (1 + budgetMargin)
    }

    /// Leaves meals open until the week costs no more than `ceiling`, for when even the cheapest dishes are too dear.
    /// Each step removes the cheapest dish that brings the week under the ceiling, or, when none does on its own, the
    /// dearest one, so as few meals as possible are lost. "Your usual meals" go only when nothing else is left.
    /// - Returns: the plan and how many meals were left open.
    func capToBudget(
        _ plan: WeeklyMealPlan,
        ceiling: Double,
        routine: MealRoutine,
        cost: (WeeklyMealPlan) -> Double
    ) -> (plan: WeeklyMealPlan, leftOpen: Int) {
        var plan = plan
        var total = cost(plan)
        var leftOpen = 0
        while total > ceiling + 0.005 {
            var choices: [(day: Int, slot: MealSlot, plan: WeeklyMealPlan, total: Double)] = []
            for (index, day) in plan.days.enumerated() {
                for slot in MealSlot.allCases where day[slot] != nil {
                    var next = plan
                    next.days[index][slot] = nil
                    choices.append((index, slot, next, cost(next)))
                }
            }
            let flexible = choices.filter { routine.type(for: $0.slot) != .fixed }
            let pool = flexible.isEmpty ? choices : flexible
            guard !pool.isEmpty else { break }
            let enough = pool.filter { $0.total <= ceiling + 0.005 }
            // Enough on its own: the one that removes least (highest remaining total). Else the biggest saving.
            guard let pick = enough.max(by: { $0.total < $1.total }) ?? pool.min(by: { $0.total < $1.total }),
                  pick.total < total - 0.005 else { break }
            plan = pick.plan
            plan.days[pick.day].budgetOpenSlots = (plan.days[pick.day].budgetOpenSlots ?? []) + [pick.slot.rawValue]
            total = pick.total
            leftOpen += 1
        }
        return (plan, leftOpen)
    }

    /// Swaps dishes for cheaper ones until the week's groceries fit the budget, or no swap saves anything more.
    /// Each step makes the swap with the biggest saving that keeps every rule: the dish suits the meal, fits the diet,
    /// allergies, dislikes and cuisines (breakfasts may come from any cuisine), isn't planned twice that day nor more
    /// than `maxTimesPerWeek` times. When no single swap helps, a dish at its weekly limit may move to the slot while
    /// one of its other days gets a cheaper dish instead. "Your usual meals" (fixed) are never swapped.
    /// - Parameters:
    ///   - cost: the week's grocery total, as the grocery list prices it.
    ///   - recipeCost: one recipe's groceries for the household, to rank swaps (the exact total decides).
    /// - Returns: the plan and how many dishes were swapped.
    func fitToBudget(
        _ plan: WeeklyMealPlan,
        recipes: [Recipe],
        preferences: UserPreferences,
        routine: MealRoutine,
        cost: (WeeklyMealPlan) -> Double,
        recipeCost: (Recipe) -> Double
    ) -> (plan: WeeklyMealPlan, swaps: Int) {
        var plan = plan
        var total = cost(plan)
        guard total > preferences.budgetWeekly else { return (plan, 0) }
        let (fitting, otherBreakfasts) = pools(recipes, preferences)
        var costs: [String: Double] = [:]
        func price(_ recipe: Recipe) -> Double {
            if let known = costs[Self.dishKey(recipe)] { return known }
            let value = recipeCost(recipe)
            costs[Self.dishKey(recipe)] = value
            return value
        }

        typealias Change = (day: Int, slot: MealSlot, recipe: Recipe)
        typealias Option = (changes: [Change], saving: Double)
        var swaps = 0
        while total > preferences.budgetWeekly && swaps < 100 {
            var timesThisWeek: [String: Int] = [:]
            for recipe in plan.allPlannedRecipes { timesThisWeek[Self.dishKey(recipe), default: 0] += 1 }
            let dishesOn = plan.days.map { day in Set(MealSlot.allCases.compactMap { day[$0] }.map(Self.dishKey)) }
            /// Dishes that may replace the one in a slot; usual meals keep theirs.
            func replacements(_ slot: MealSlot) -> [Recipe] {
                guard routine.type(for: slot) != .fixed else { return [] }
                return (slot == .breakfast ? fitting + otherBreakfasts : fitting).filter { $0.suits(slot) }
            }
            /// Swaps of one dish for a cheaper one that isn't on that day and is below its weekly limit.
            func singles() -> [Option] {
                var options: [Option] = []
                for (index, day) in plan.days.enumerated() {
                    for slot in MealSlot.allCases {
                        guard let current = day[slot] else { continue }
                        for candidate in replacements(slot) {
                            let key = Self.dishKey(candidate)
                            guard !dishesOn[index].contains(key),
                                  timesThisWeek[key, default: 0] < Self.maxTimesPerWeek else { continue }
                            let saving = price(current) - price(candidate)
                            if saving > 0.01 { options.append(([(index, slot, candidate)], saving)) }
                        }
                    }
                }
                return options
            }
            /// A dish at its weekly limit takes the slot, and one of its other days gets a dish below its limit
            /// instead. Without these, a dear dish can stay when the only cheaper dishes left are on its day.
            func exchanges() -> [Option] {
                var options: [Option] = []
                for (index, day) in plan.days.enumerated() {
                    for slot in MealSlot.allCases {
                        guard let current = day[slot] else { continue }
                        for candidate in replacements(slot) {
                            let key = Self.dishKey(candidate)
                            guard !dishesOn[index].contains(key),
                                  timesThisWeek[key, default: 0] >= Self.maxTimesPerWeek else { continue }
                            for (other, otherDay) in plan.days.enumerated() where other != index {
                                for otherSlot in MealSlot.allCases where otherDay[otherSlot].map(Self.dishKey) == key {
                                    for stand in replacements(otherSlot) {
                                        let standKey = Self.dishKey(stand)
                                        // The swapped-out dish frees one of its own week's places.
                                        let times = timesThisWeek[standKey, default: 0]
                                            - (standKey == Self.dishKey(current) ? 1 : 0)
                                        guard !dishesOn[other].contains(standKey), times < Self.maxTimesPerWeek else { continue }
                                        let saving = price(current) - price(stand)
                                        if saving > 0.01 {
                                            options.append(([(index, slot, candidate), (other, otherSlot, stand)], saving))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                return options
            }
            // The estimate ranks the swaps; the first that lowers the real total (shared ingredients and pack
            // prices make it differ) is made. Exchanges are only looked for when no single swap helps.
            func improve(with options: [Option]) -> Bool {
                for option in options.sorted(by: { $0.saving > $1.saving }).prefix(8) {
                    var next = plan
                    for change in option.changes { next.days[change.day][change.slot] = change.recipe }
                    let nextTotal = cost(next)
                    if nextTotal < total - 0.01 {
                        plan = next
                        total = nextTotal
                        swaps += option.changes.count
                        return true
                    }
                }
                return false
            }
            guard improve(with: singles()) || improve(with: exchanges()) else { break }
        }
        return (plan, swaps)
    }

    /// Home meals the routine asks for in a week but that got no recipe because every matching dish had
    /// reached its limit.
    static func unplannedMeals(in plan: WeeklyMealPlan, routine: MealRoutine, preferences: UserPreferences) -> Int {
        let wantsBreakfast = preferences.breakfastRecipePreference == .includeRecipes && routine.breakfastType != .outside
        let wanted = [wantsBreakfast, routine.lunchType != .outside, routine.dinnerType != .outside].filter { $0 }.count
        let openForBudget = plan.days.map { $0.budgetOpenSlots?.count ?? 0 }.reduce(0, +)
        return max(0, wanted * plan.days.count - plan.allPlannedRecipes.count - openForBudget)
    }

    /// Recipes are the same dish when their names match.
    private static func dishKey(_ recipe: Recipe) -> String {
        recipe.name.lowercased()
    }

    /// Recipes that fit the diet, avoid allergies and dislikes, and match the chosen cuisines.
    func filterRecipes(
        _ recipes: [Recipe],
        _ preferences: UserPreferences
    ) -> [Recipe] {
        let dislikeTokens = preferences.dislikes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return recipes.filter { recipe in
            switch preferences.dietType {
            case "Vegetarian":
                if recipe.containsMeat { return false }
            case "Vegan":
                if recipe.containsAnimalProducts { return false }
            default:
                break
            }

            for allergy in preferences.allergies {
                let token = allergy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !token.isEmpty else { continue }
                if recipe.ingredients.contains(where: {
                    $0.ingredient.name.lowercased().contains(token)
                }) {
                    return false
                }
            }

            for dislike in dislikeTokens {
                if recipe.ingredients.contains(where: {
                    $0.ingredient.name.lowercased().contains(dislike)
                }) {
                    return false
                }
            }

            if !preferences.cuisines.isEmpty {
                let match = preferences.cuisines.contains {
                    $0.caseInsensitiveCompare(recipe.cuisine) == .orderedSame
                }
                if !match { return false }
            }

            return true
        }
    }

    /// Picks from recipes that are still allowed today. Fixed keeps the first matching recipe until it reaches
    /// its weekly limit, then the next; home cooked and flexible choose at random among the least-used dishes.
    private func selectMeal(
        type: MealType,
        from recipes: [Recipe],
        timesThisWeek: [String: Int]
    ) -> Recipe? {
        switch type {
        case .outside:
            return nil
        case .fixed:
            return recipes.first
        case .homeCooked, .flexible:
            let fewest = recipes.map { timesThisWeek[Self.dishKey($0), default: 0] }.min()
            return recipes.filter { timesThisWeek[Self.dishKey($0), default: 0] == fewest }.randomElement()
        }
    }
}
