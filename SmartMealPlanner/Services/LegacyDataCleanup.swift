//
//  LegacyDataCleanup.swift
//  SmartMealPlanner
//
//  Removes data that earlier versions saved and this one must not keep: recipes from Spoonacular (its terms require
//  deleting data from its API once it is no longer used) and recipes written by AI, including a saved plan made from
//  them. Runs at every launch; it costs nothing once the data is gone.
//

import Foundation

enum LegacyDataCleanup {
    /// Recipe files earlier versions kept in Application Support.
    static let oldRecipeFiles = ["searched-recipes.json", "ai-recipes.json"]

    static func run(defaults: UserDefaults = .standard,
                    folder: URL = .applicationSupportDirectory) {
        for name in oldRecipeFiles {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        if let data = defaults.data(forKey: PlanningViewModel.Keys.lastPlan), planHasOldRecipes(data) {
            defaults.removeObject(forKey: PlanningViewModel.Keys.lastPlan)
        }
    }

    /// Whether a saved plan has a recipe from Spoonacular or one written by AI.
    static func planHasOldRecipes(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let plan = try? decoder.decode(AISuggestedWeekPlan.self, from: data) else {
            // Unreadable by this version: nothing can be shown from it, and it may hold old recipes.
            return true
        }
        return plan.weeklyMealPlan.allPlannedRecipes.contains { recipe in
            recipe.isAIGenerated || recipe.cookbookReference?.hasPrefix("Spoonacular") == true
                || recipe.imageURL?.contains("spoonacular.com") == true
        }
    }
}
