//
//  PlanningViewModel.swift
//  SmartMealPlanner
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class PlanningViewModel: ObservableObject {

    @Published var suggestedPlan: AISuggestedWeekPlan?
    @Published var isLoading = false
    @Published var lastError: String?

    /// Recipes and offers the planner chooses from.
    struct Catalog {
        var recipes: [Recipe]
        var offers: [SupermarketOffer]

        /// The JSON files bundled with the app.
        static func bundled() throws -> Catalog {
            Catalog(
                recipes: try JSONLoader.load("recipes", as: [Recipe].self),
                offers: try JSONLoader.load("offers", as: [SupermarketOffer].self)
            )
        }
    }

    static let missingPreferencesMessage = "Save your preferences on the Preferences tab first."
    static let missingRoutineMessage = "Set your meal routine (Preferences → Meal Routine) first."

    private let ai: AIPlanningService
    private let defaults: UserDefaults
    private let loadCatalog: () throws -> Catalog

    enum Keys {
        /// Bumped when `AISuggestedWeekPlan` shape changes (e.g. single-day → full week).
        static let lastPlan = "lastAISuggestedWeekPlan_v2"
    }

    init(
        ai: AIPlanningService,
        defaults: UserDefaults = .standard,
        loadCatalog: @escaping () throws -> Catalog = Catalog.bundled
    ) {
        self.ai = ai
        self.defaults = defaults
        self.loadCatalog = loadCatalog
        loadCachedPlan()
    }

    func loadCachedPlan() {
        guard let data = defaults.data(forKey: Keys.lastPlan) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        suggestedPlan = try? decoder.decode(AISuggestedWeekPlan.self, from: data)
    }

    func generatePlan() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let catalog = try loadCatalog()

            guard let prefs = UserPreferences.load(from: defaults) else {
                lastError = Self.missingPreferencesMessage
                return
            }

            guard let routine = MealRoutine.load(from: defaults) else {
                lastError = Self.missingRoutineMessage
                return
            }

            let plan = try await ai.generateWeeklySuggestions(
                preferences: prefs,
                routine: routine,
                recipes: catalog.recipes,
                weeklyOffers: catalog.offers
            )
            suggestedPlan = plan
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let encoded = try? encoder.encode(plan) {
                defaults.set(encoded, forKey: Keys.lastPlan)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearPlan() {
        suggestedPlan = nil
        defaults.removeObject(forKey: Keys.lastPlan)
    }
}
