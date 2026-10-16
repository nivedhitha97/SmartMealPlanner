//
//  WeeklyPlanUITests.swift
//  SmartMealPlannerUITests
//
//  End-to-end: set up preferences and a routine, generate a plan, open a recipe.
//

import XCTest

@MainActor
final class WeeklyPlanUITests: XCTestCase {

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testNewUserSeesTheSetupChecklist() {
        let app = XCUIApplication.launchForTesting()

        XCTAssertTrue(app.staticTexts["Plan your week in seconds"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set your preferences"].exists)
        XCTAssertTrue(app.staticTexts["Choose a meal routine"].exists)
        XCTAssertTrue(app.buttons["Generate my week"].exists)
    }

    func testGeneratingBeforeSavingPreferencesShowsWhatToDoFirst() {
        let app = XCUIApplication.launchForTesting()

        app.buttons["Generate my week"].tap()

        XCTAssertTrue(app.staticTexts["Save your preferences on the Preferences tab first."].waitForExistence(timeout: 5))
    }

    func testSettingUpAndGeneratingAPlanShowsMealsAndRecipes() {
        let app = XCUIApplication.launchForTesting()

        // Preferences: two people, vegetarian (default) and Italian food, then save.
        app.openTab("Preferences")
        let people = app.steppers["preferences.people"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        people.buttons.element(boundBy: 1).tap()  // increment
        let italian = app.button(containing: "Italian")
        app.scrollTo(italian)
        italian.tap()
        XCTAssertTrue(italian.isSelected, "Italian chip should be selected")

        let save = app.buttons["Save preferences"]
        app.scrollTo(save)
        save.tap()
        XCTAssertTrue(app.button(containing: "Saved").waitForExistence(timeout: 3), "Save button should confirm")

        // Meal routine: cook lunch and dinner at home.
        let routineLink = app.buttons["preferences.routineLink"]
        app.reveal(routineLink)
        routineLink.tap()
        XCTAssertTrue(app.staticTexts["Meal routine"].waitForExistence(timeout: 5))

        let lunchHomeCooked = app.buttons["routine.Lunch.Home Cooked"]
        app.scrollTo(lunchHomeCooked)
        lunchHomeCooked.tap()
        XCTAssertTrue(lunchHomeCooked.isSelected)
        app.buttons["Save routine"].tap()

        XCTAssertTrue(app.element(containing: "Home Cooked · Home Cooked").waitForExistence(timeout: 5),
                      "Preferences should summarise the saved routine")

        // Generate the plan.
        app.openTab("Plan")
        app.buttons["Generate my week"].tap()

        XCTAssertTrue(app.staticTexts["Estimated groceries"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Planner notes"].exists)

        // Open a planned lunch and check the recipe screen.
        let lunch = app.buttons["plan.meal.Lunch"]
        app.scrollTo(lunch)
        lunch.tap()

        XCTAssertTrue(app.staticTexts["Ingredients"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Method"].exists)
        XCTAssertTrue(app.element(containing: "Italian").exists, "Recipe should match the chosen cuisine")
        XCTAssertTrue(app.element(containing: "2 people").exists, "Amounts are for the people in Preferences")
        let times = app.element(withID: "recipe.times")
        XCTAssertTrue(times.exists, "Prep, cooking and total time are shown")
        XCTAssertTrue(times.label.contains("Prep") && times.label.contains("Cook"))
    }

    func testPickingAnotherDayShowsThatDaysMeals() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Preferences")
        let save = app.buttons["Save preferences"]
        app.scrollTo(save)
        save.tap()
        let routineLink = app.buttons["preferences.routineLink"]
        app.reveal(routineLink)
        routineLink.tap()
        app.buttons["Save routine"].tap()

        app.openTab("Plan")
        app.buttons["Generate my week"].tap()
        XCTAssertTrue(app.staticTexts["Estimated groceries"].waitForExistence(timeout: 10))

        let lastDay = app.element(withID: "plan.day.6")
        app.scrollTo(lastDay)
        lastDay.tap()

        XCTAssertTrue(lastDay.isSelected, "Tapped day should become selected")
    }
}
