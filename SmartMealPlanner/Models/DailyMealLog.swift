//
//  DailyMealLog.swift
//  SmartMealPlanner
//

import Foundation

struct DailyMealLog: Codable {
    var date: Date
    var breakfast: Recipe?
    var lunch: Recipe?
    var dinner: Recipe?

    private var allMeals: [Recipe] {
        var meals: [Recipe] = []
        if let breakfast { meals.append(breakfast) }
        if let lunch { meals.append(lunch) }
        if let dinner { meals.append(dinner) }
        return meals
    }

    private func nutritionTotal(value: (Ingredient) -> Double) -> Double {
        var total: Double = 0
        for recipe in allMeals {
            for row in recipe.ingredients {
                let scale = recipe.quantity(of: row, forPeople: 1) / 100.0  // per person
                total += value(row.ingredient) * scale
            }
        }
        return total
    }

    var totalCalories: Double { nutritionTotal { $0.calories } }
    var totalProtein: Double { nutritionTotal { $0.protein } }
    var totalCarbs: Double { nutritionTotal { $0.carbs } }
    var totalFiber: Double { nutritionTotal { $0.fiber ?? 0 } }
    var totalFat: Double { nutritionTotal { $0.fat } }
}

enum NutritionTotals {
    static func aggregate(recipes: [Recipe]) -> (calories: Double, protein: Double, carbs: Double, fat: Double) {
        var cal = 0.0, pro = 0.0, car = 0.0, fat = 0.0
        for recipe in recipes {
            for row in recipe.ingredients {
                let scale = recipe.quantity(of: row, forPeople: 1) / 100.0  // per person
                cal += row.ingredient.calories * scale
                pro += row.ingredient.protein * scale
                car += row.ingredient.carbs * scale
                fat += row.ingredient.fat * scale
            }
        }
        return (cal, pro, car, fat)
    }
}
