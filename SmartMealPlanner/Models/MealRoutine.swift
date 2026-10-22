//
//  MealRoutine.swift
//  SmartMealPlanner
//
//  Created by Nivedhitha on 29/12/2025.
//

import Foundation

struct MealRoutine: Codable, Equatable {
    var breakfastType: MealType
    var lunchType: MealType
    var dinnerType: MealType

    /// What the Meal routine screen shows before anything has been saved.
    static let `default` = MealRoutine(breakfastType: .fixed, lunchType: .outside, dinnerType: .homeCooked)

    static let defaultsKey = "mealRoutine"

    func type(for slot: MealSlot) -> MealType {
        switch slot {
        case .breakfast: return breakfastType
        case .lunch: return lunchType
        case .dinner: return dinnerType
        }
    }

    /// "Fixed · Outside · Home Cooked" (breakfast · lunch · dinner).
    var summary: String {
        [breakfastType, lunchType, dinnerType].map(\.rawValue).joined(separator: " · ")
    }

    static func load(from defaults: UserDefaults = .standard) -> MealRoutine? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(MealRoutine.self, from: data)
    }

    /// Returns false if encoding failed and nothing was written.
    @discardableResult
    func save(to defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case fixed = "Fixed"
    case flexible = "Flexible"
    case homeCooked = "Home Cooked"
    case outside = "Outside"
    
    var id: String { rawValue }
}
