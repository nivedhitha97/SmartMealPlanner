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
        XCTAssertTrue(app.staticTexts["Deals near you"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(containing: "Broccoli 500g").exists, "All offers show by default")

        app.button(containing: "Meat").tap()

        XCTAssertTrue(app.element(containing: "Chicken Breast Fillets 400g").waitForExistence(timeout: 3))
        XCTAssertFalse(app.element(containing: "Broccoli 500g").exists, "Produce offers are hidden under Meat")

        app.button(containing: "All").tap()
        XCTAssertTrue(app.element(containing: "Broccoli 500g").waitForExistence(timeout: 3))
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

    private func postcodeField(in app: XCUIApplication) -> XCUIElement {
        app.openTab("Preferences")
        let field = app.textFields["Postcode (e.g. 1012 AB)"]
        app.scrollTo(field)
        return field
    }
}
