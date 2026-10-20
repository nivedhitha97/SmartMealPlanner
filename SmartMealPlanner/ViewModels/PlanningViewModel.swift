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

    /// Offers and ingredient prices the planner prices groceries with (and, in tests, extra recipes).
    /// Recipes come from recipe search (`discoverRecipes`); the app ships none of its own.
    struct Catalog {
        var recipes: [Recipe] = []
        var offers: [SupermarketOffer]
        var ingredientPrices: [IngredientPrice] = []

        /// The latest offers and prices from the grocery feed, plus the deals the user added.
        static func live() async throws -> Catalog {
            try await live(from: GroceryDataServices.shared)
        }

        static func live(from service: GroceryDataService) async throws -> Catalog {
            let grocery = await service.latest()
            let offers = MyOffersStore.merged(grocery.offers, with: MyOffersStore.saved())
            return Catalog(offers: offers, ingredientPrices: grocery.prices)
        }
    }

    static let missingPreferencesMessage = "Save your preferences on the Preferences tab first."
    static let missingRoutineMessage = "Set your meal routine (Preferences → Meal Routine) first."
    static let noRecipesMessage = "No recipes found for your preferences. Try adding cuisines or removing exclusions."

    private let ai: AIPlanningService
    private let defaults: UserDefaults
    private let loadCatalog: () async throws -> Catalog
    /// The recipes to plan with: searched for the preferences, or the saved ones offline (Recipe discovery).
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
            guard let prefs = UserPreferences.load(from: defaults) else {
                lastError = Self.missingPreferencesMessage
                return
            }

            guard let routine = MealRoutine.load(from: defaults) else {
                lastError = Self.missingRoutineMessage
                return
            }

            async let loadedCatalog = loadCatalog()
            let discovered = await discoverRecipes(prefs)
            var catalog = try await loadedCatalog
            let known = Set(catalog.recipes.map { $0.name.lowercased() })
            catalog.recipes += discovered.recipes.filter { !known.contains($0.name.lowercased()) }
            guard !catalog.recipes.isEmpty else {
                // No recipes: offline with none saved, or no recipe source. Any plan already made stays.
                lastError = discovered.note ?? Self.noRecipesMessage
                return
            }
            let discoveryNote = discovered.recipes.isEmpty
                ? discovered.note
                : discovered.source.plannerNote

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
