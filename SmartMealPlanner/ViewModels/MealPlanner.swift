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
        let filtered = filterRecipes(recipes, preferences)
        var anyCuisine = preferences
        anyCuisine.cuisines = []
        let otherBreakfasts = filterRecipes(recipes, anyCuisine).filter { recipe in
            recipe.meals?.contains(MealSlot.breakfast.rawValue) == true && !filtered.contains { $0.id == recipe.id }
        }
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

    /// Home meals the routine asks for in a week but that got no recipe because every matching dish had
    /// reached its limit.
    static func unplannedMeals(in plan: WeeklyMealPlan, routine: MealRoutine, preferences: UserPreferences) -> Int {
        let wantsBreakfast = preferences.breakfastRecipePreference == .includeRecipes && routine.breakfastType != .outside
        let wanted = [wantsBreakfast, routine.lunchType != .outside, routine.dinnerType != .outside].filter { $0 }.count
        return max(0, wanted * plan.days.count - plan.allPlannedRecipes.count)
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
