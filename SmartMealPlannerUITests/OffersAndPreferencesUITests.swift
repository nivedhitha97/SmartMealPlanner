//
//  OffersAndPreferencesUITests.swift
//  SmartMealPlannerUITests
//
//  Offers filtering and the Preferences postcode field.
//

import XCTest

@MainActor
final class OffersAndPreferencesUITests: XCTestCase {

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testFilteringOffersByCategory() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Offers")
        XCTAssertTrue(app.staticTexts["Deals near you"].waitForExistence(timeout: 5), "Offers screen opens")
        XCTAssertTrue(app.element(containing: "Broccoli 500g").waitForExistence(timeout: 5), "All offers show by default")

        app.button(containing: "Meat").tap()

        XCTAssertTrue(app.element(containing: "Chicken Breast Fillets 400g").waitForExistence(timeout: 3), "Meat offer shows")
        XCTAssertFalse(app.element(containing: "Broccoli 500g").exists, "Produce offers are hidden under Meat")

        app.buttons["All"].tap()  // the category chip, not "All stores"
        XCTAssertTrue(app.element(containing: "Broccoli 500g").waitForExistence(timeout: 3), "All shows every offer again")
    }

    func testInvalidPostcodeShowsAnError() {
        let app = XCUIApplication.launchForTesting()
        let field = postcodeField(in: app)

        field.tap()
        field.typeText("0123AB")

        XCTAssertTrue(app.element(containing: "Enter a Dutch postcode").waitForExistence(timeout: 3))
    }

    func testValidPostcodeShowsItsRegion() {
        let app = XCUIApplication.launchForTesting()
        let field = postcodeField(in: app)

        field.tap()
        field.typeText("1012AB")

        // The region comes from the postcode itself, so this works even if the city lookup is offline.
        XCTAssertTrue(app.element(containing: "NL-North").waitForExistence(timeout: 15))
        XCTAssertTrue(app.element(containing: "1012 AB").exists)
    }

    func testFirstSaveKeepsThePostcodeAndChoices() {
        let app = XCUIApplication.launchForTesting()
        let field = postcodeField(in: app)
        field.tap()
        field.typeText("1062JB\n")  // return closes the keyboard

        // Save straight away, before the postcode lookup has had time to finish.
        let save = app.buttons["preferences.save"]
        app.scrollTo(save)
        save.tap()
        XCTAssertTrue(app.button(containing: "Saved").waitForExistence(timeout: 3), "First tap saves")

        // Relaunch without wiping data: the postcode must have been saved.
        app.terminate()
        let relaunched = XCUIApplication.launchForTesting(resetState: false)
        let savedField = postcodeField(in: relaunched)
        XCTAssertEqual(savedField.value as? String, "1062 JB")
    }

    func testEditsSurviveAVisitToMealRoutine() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Preferences")
        let save = app.buttons["preferences.save"]
        app.scrollTo(save)
        save.tap()  // something saved, so the screen has preferences to (wrongly) reload

        let italian = app.button(containing: "Italian")
        app.scrollUpTo(italian)
        italian.tap()
        XCTAssertTrue(italian.isSelected)

        let routineLink = app.buttons["preferences.routineLink"]
        app.scrollTo(routineLink)
        routineLink.tap()
        XCTAssertTrue(app.staticTexts["Meal routine"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let italianAgain = app.button(containing: "Italian")
        if !italianAgain.isHittable { app.scrollUpTo(italianAgain) }
        XCTAssertTrue(italianAgain.isSelected, "Unsaved choice is kept after coming back")
    }

    private func postcodeField(in app: XCUIApplication) -> XCUIElement {
        app.openTab("Preferences")
        let field = app.textFields["Postcode (e.g. 1012 AB)"]
        app.scrollTo(field)
        return field
    }
}
