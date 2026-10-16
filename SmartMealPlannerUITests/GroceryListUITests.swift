//
//  GroceryListUITests.swift
//  SmartMealPlannerUITests
//
//  Adding offers to the grocery list, the store filter on Offers, and the editable list with its filters and
//  totals. Uses the bundled sample offers (see launchForTesting).
//

import XCTest

@MainActor
final class GroceryListUITests: XCTestCase {

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testStoreFilterShowsOnlyThatStoresOffers() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Offers")
        XCTAssertTrue(app.element(containing: "Broccoli 500g").waitForExistence(timeout: 5))

        app.buttons["Lidl"].tap()

        XCTAssertTrue(app.element(containing: "Broccoli 500g").waitForExistence(timeout: 3))
        XCTAssertFalse(app.element(containing: "Basmati Rice 1kg").exists, "Jumbo's offer is hidden under Lidl")

        app.buttons["All stores"].tap()
        XCTAssertTrue(app.element(containing: "Basmati Rice 1kg").waitForExistence(timeout: 3))
    }

    func testAddingOffersPutsThemOnTheListWithTotals() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Offers")

        let addBroccoli = app.buttons["offer.add.Broccoli 500g"]
        XCTAssertTrue(addBroccoli.waitForExistence(timeout: 5))
        addBroccoli.tap()
        addBroccoli.tap()
        XCTAssertTrue(addBroccoli.label.contains("2 on your list"), "Second tap adds one more")

        let addRice = app.buttons["offer.add.Basmati Rice 1kg"]
        app.scrollTo(addRice)
        addRice.tap()

        app.openTab("List")
        XCTAssertTrue(app.staticTexts["Grocery list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(withID: "list.item.Broccoli 500g").exists)
        XCTAssertTrue(app.element(withID: "list.item.Basmati Rice 1kg").exists)
        // 2 × €1.49 + €2.29 (the decimal separator depends on the simulator's region)
        let total = app.element(withID: "list.total").label
        XCTAssertTrue(total.contains("5,27") || total.contains("5.27"), "Total is €5.27, not \(total)")

        // Filter by store: only Lidl's item and Lidl's total.
        app.buttons["Lidl"].tap()
        XCTAssertTrue(app.element(containing: "2,98").waitForExistence(timeout: 3)
                      || app.element(containing: "2.98").exists)
        XCTAssertFalse(app.element(withID: "list.item.Basmati Rice 1kg").exists)
    }

    func testOwnItemsCanBeAddedEditedTickedAndDeleted() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("List")
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))

        // Add
        app.buttons["list.addItem"].tap()
        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Bread")
        let price = app.textFields["editor.price"]
        price.tap()
        price.typeText("2")
        app.buttons["editor.save"].tap()

        let row = app.element(withID: "list.item.Bread")
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // Edit: one more
        row.tap()
        let stepper = app.steppers["editor.quantity"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons.element(boundBy: 1).tap()
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.element(containing: "2 × ").waitForExistence(timeout: 3), "Quantity shows on the row")

        // Tick off
        app.buttons["list.check.Bread"].tap()
        XCTAssertTrue(app.buttons["Ticked off: Bread"].waitForExistence(timeout: 3))

        // Delete
        row.tap()
        let delete = app.buttons["editor.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.staticTexts["Your list is empty"].waitForExistence(timeout: 5))
    }

    func testPlanGroceriesAppearOnTheListTab() {
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
        let card = app.element(withID: "plan.groceryList")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.staticTexts["Grocery list"].waitForExistence(timeout: 5), "The card opens the List tab")
        XCTAssertTrue(app.element(containing: "From your plan").waitForExistence(timeout: 5))
    }
}
