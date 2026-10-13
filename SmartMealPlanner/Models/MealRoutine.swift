//
//  MealRoutine.swift
//  SmartMealPlanner
//
//  Created by Nivedhitha on 29/12/2025.
//

import Foundation

struct MealRoutine: Codable {
    var breakfastType: MealType
    var lunchType: MealType
    var dinnerType: MealType

    /// "Fixed · Outside · Home Cooked" (breakfast · lunch · dinner).
    var summary: String {
        [breakfastType, lunchType, dinnerType].map(\.rawValue).joined(separator: " · ")
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case fixed = "Fixed"
    case flexible = "Flexible"
    case homeCooked = "Home Cooked"
    case outside = "Outside"
    
    var id: String { rawValue }
}
