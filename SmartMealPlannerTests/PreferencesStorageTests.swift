//
//  PreferencesStorageTests.swift
//  SmartMealPlannerTests
//
//  Saving and loading what the Preferences screen writes, using an isolated UserDefaults suite
//  so the app's real data is never touched.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Preferences storage")
final class PreferencesStorageTests {

    private let suiteName = "PreferencesStorageTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func loadReturnsNilWhenNothingWasSaved() {
        #expect(UserPreferences.load(from: defaults) == nil)
    }

    @Test func savedPreferencesLoadBackUnchanged() {
        let preferences = UserPreferences(
            dietType: "Vegan",
            cuisines: ["Asian", "Indian"],
            dislikes: ["olives"],
            allergies: ["peanuts"],
            budgetWeekly: 85,
            shoppingRegion: "Amsterdam, NL-North",
            postcode: "1012 AB",
            breakfastRecipePreference: .granolaMuesliOnly
        )

        #expect(preferences.save(to: defaults))
        #expect(UserPreferences.load(from: defaults) == preferences)
    }

    @Test func preferencesSavedBeforePostcodesExistedStillLoad() throws {
        // Shape written by earlier versions of the app: no postcode, region or breakfast mode.
        let oldJSON = #"{"dietType":"Vegetarian","cuisines":["Italian"],"dislikes":[],"allergies":[],"budgetWeekly":50}"#
        defaults.set(Data(oldJSON.utf8), forKey: UserPreferences.defaultsKey)

        let loaded = try #require(UserPreferences.load(from: defaults))

        #expect(loaded.cuisines == ["Italian"])
        #expect(loaded.postcode.isEmpty)
        #expect(loaded.shoppingRegion.isEmpty)
        #expect(loaded.breakfastRecipePreference == .includeRecipes)
    }

    @Test func corruptDataLoadsAsNothingSaved() {
        defaults.set(Data("not json".utf8), forKey: UserPreferences.defaultsKey)

        #expect(UserPreferences.load(from: defaults) == nil)
    }

    @Test func routineSummaryListsBreakfastLunchAndDinner() {
        let routine = MealRoutine(breakfastType: .fixed, lunchType: .outside, dinnerType: .homeCooked)

        #expect(routine.summary == "Fixed · Outside · Home Cooked")
    }
}
