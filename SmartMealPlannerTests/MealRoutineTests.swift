//
//  MealRoutineTests.swift
//  SmartMealPlannerTests
//
//  Defaults and storage behind the Meal routine screen.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Meal routine screen")
struct MealRoutineTests {

    private let storage = IsolatedDefaults()

    @Test func defaultRoutineIsFixedBreakfastOutsideLunchHomeCookedDinner() {
        #expect(MealRoutine.default == MealRoutine(breakfastType: .fixed, lunchType: .outside, dinnerType: .homeCooked))
    }

    @Test func nothingIsLoadedBeforeARoutineIsSaved() {
        #expect(MealRoutine.load(from: storage.defaults) == nil)
    }

    @Test(arguments: MealType.allCases)
    func savedRoutineLoadsBackUnchanged(type: MealType) {
        let routine = MealRoutine(breakfastType: type, lunchType: .homeCooked, dinnerType: .flexible)

        #expect(routine.save(to: storage.defaults))
        #expect(MealRoutine.load(from: storage.defaults) == routine)
    }

    @Test func savingAgainReplacesThePreviousRoutine() {
        MealRoutine.default.save(to: storage.defaults)
        let updated = MealRoutine(breakfastType: .outside, lunchType: .outside, dinnerType: .outside)

        updated.save(to: storage.defaults)

        #expect(MealRoutine.load(from: storage.defaults) == updated)
    }

    @Test func corruptDataLoadsAsNothingSaved() {
        storage.defaults.set(Data("not json".utf8), forKey: MealRoutine.defaultsKey)

        #expect(MealRoutine.load(from: storage.defaults) == nil)
    }

    @Test func routineIsStoredInTheFormatEarlierVersionsUsed() throws {
        // Earlier versions wrote the raw-value strings; make sure those still decode.
        let json = #"{"breakfastType":"Fixed","lunchType":"Outside","dinnerType":"Home Cooked"}"#
        storage.defaults.set(Data(json.utf8), forKey: MealRoutine.defaultsKey)

        #expect(try #require(MealRoutine.load(from: storage.defaults)) == .default)
    }
}
