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

    /// Recipes, offers and ingredient prices the planner chooses from.
    struct Catalog {
        var recipes: [Recipe]
        var offers: [SupermarketOffer]
        var ingredientPrices: [IngredientPrice] = []

        /// Bundled recipes with the latest offers and prices from the live grocery feed.
        static func live() async throws -> Catalog {
            try await live(from: GroceryDataServices.shared)
        }

        static func live(from service: GroceryDataService) async throws -> Catalog {
            let recipes = try JSONLoader.load("recipes", as: [Recipe].self)
            let grocery = await service.latest()
            let offers = MyOffersStore.merged(grocery.offers, with: MyOffersStore.saved())
            return Catalog(recipes: recipes, offers: offers, ingredientPrices: grocery.prices)
        }
    }

    static let missingPreferencesMessage = "Save your preferences on the Preferences tab first."
    static let missingRoutineMessage = "Set your meal routine (Preferences → Meal Routine) first."

    private let ai: AIPlanningService
    private let defaults: UserDefaults
    private let loadCatalog: () async throws -> Catalog
    /// AI recipes for the preferences (Recipe discovery), added to the catalog when that preference is on.
    private let discoverRecipes: (UserPreferences) async -> DiscoveredRecipes

    enum Keys {
        /// Bumped when `AISuggestedWeekPlan` shape changes (e.g. single-day → full week).
        static let lastPlan = "lastAISuggestedWeekPlan_v2"
    }

    init(
        ai: AIPlanningService,
        defaults: UserDefaults = .standard,
        loadCatalog: @escaping () async throws -> Catalog = Catalog.live,
        discoverRecipes: @escaping (UserPreferences) async -> DiscoveredRecipes = { await RecipeDiscovery.shared.recipes(for: $0) }
    ) {
        self.ai = ai
        self.defaults = defaults
        self.loadCatalog = loadCatalog
        self.discoverRecipes = discoverRecipes
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
            var catalog = try await loadCatalog()

            guard let prefs = UserPreferences.load(from: defaults) else {
                lastError = Self.missingPreferencesMessage
                return
            }

            guard let routine = MealRoutine.load(from: defaults) else {
                lastError = Self.missingRoutineMessage
                return
            }

            var discoveryNote: String?
            if prefs.discoverRecipes {
                let discovered = await discoverRecipes(prefs)
                let known = Set(catalog.recipes.map { $0.name.lowercased() })
                let new = discovered.recipes.filter { !known.contains($0.name.lowercased()) }
                catalog.recipes += new
                discoveryNote = new.isEmpty
                    ? discovered.note
                    : "Includes \(new.count) recipes \(discovered.source.description) (marked on each recipe)."
            }

            var plan = try await ai.generateWeeklySuggestions(
                preferences: prefs,
                routine: routine,
                recipes: catalog.recipes,
                weeklyOffers: catalog.offers,
                ingredientPrices: catalog.ingredientPrices
            )
            if let discoveryNote {
                plan.aiSummary += " " + discoveryNote
            }
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
