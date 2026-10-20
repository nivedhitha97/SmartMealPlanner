//
//  ScreenshotTests.swift
//  SmartMealPlannerUITests
//
//  Takes the README screenshots (docs/screenshots) with live offers and a realistic week. Skipped unless a folder is
//  given, so it never runs in normal test runs:
//
//    TEST_RUNNER_SCREENSHOT_DIR="$PWD/docs/screenshots" xcodebuild test -scheme SmartMealPlanner \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SmartMealPlannerUITests/ScreenshotTests
//

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {

    private var folder: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_SCREENSHOT_DIR to take the README screenshots")
        }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func testTakeReadmeScreenshots() throws {
        // Launch screen, held long enough to capture.
        var app = XCUIApplication.launchForTesting(skipSplash: false, liveData: true,
                                                   extraArguments: [LaunchFlag.splashSeconds, "4"])
        sleep(2)
        try capture("01-launch")
        app.terminate()

        app = XCUIApplication.launchForTesting(liveData: true)

        // Preferences: two people, non-vegetarian, five cuisines (enough recipes for a full week), Amsterdam postcode with its
        // nearby supermarkets.
        app.openTab("Preferences")
        let people = app.steppers["preferences.people"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        people.buttons.element(boundBy: 1).tap()
        app.buttons["Non-Vegetarian"].tap()  // the largest recipe choice, so the whole week is planned
        for cuisine in ["Italian", "Greek", "Indian", "Asian", "Mexican"] {
            let chip = app.button(containing: cuisine)
            app.scrollTo(chip)
            chip.tap()
        }
        let postcode = app.textFields["Postcode (e.g. 1012 AB)"]
        app.scrollTo(postcode)
        postcode.tap()
        postcode.typeText("1062JB\n")
        XCTAssertTrue(app.element(withID: "preferences.nearbyStores").waitForExistence(timeout: 30), "nearby stores")
        let save = app.buttons["preferences.save"]
        app.scrollTo(save, maxSwipes: 14)
        save.tap()
        let routineLink = app.buttons["preferences.routineLink"]
        app.reveal(routineLink)
        routineLink.tap()
        let lunch = app.buttons["routine.Lunch.Home Cooked"]
        app.scrollTo(lunch)
        lunch.tap()
        app.buttons["Save routine"].tap()
        sleep(1)

        // Weekly plan.
        app.openTab("Plan")
        app.buttons["Generate my week"].tap()
        XCTAssertTrue(app.staticTexts["Estimated groceries"].waitForExistence(timeout: 30))
        sleep(2)
        try capture("02-weekly-plan")

        let meal = app.buttons["plan.meal.Lunch"]
        app.scrollTo(meal)
        app.swipeUp()
        try capture("03-meals")

        // Recipe detail.
        app.reveal(meal)
        meal.tap()
        XCTAssertTrue(app.staticTexts["Ingredients"].waitForExistence(timeout: 5))
        sleep(2)  // photo
        try capture("04-recipe")

        // Offers with live data.
        app.openTab("Offers")
        XCTAssertTrue(app.staticTexts["Deals near you"].waitForExistence(timeout: 30))
        let lidl = app.buttons["Lidl"]  // a store whose offers have product photos
        if lidl.waitForExistence(timeout: 5) { lidl.tap() }
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        top.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        sleep(4)  // product photos
        try capture("05-offers")

        // Grocery list from the plan, with a few items ticked off.
        app.openTab("List")
        XCTAssertTrue(app.staticTexts["Grocery list"].waitForExistence(timeout: 5))
        let checks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'list.check.'"))
        for index in 0..<min(3, checks.count) where app.canTap(checks.element(boundBy: index)) {
            checks.element(boundBy: index).tap()
        }
        sleep(1)
        try capture("06-grocery-list")

        // Preferences, from the top.
        app.openTab("Preferences")
        app.scrollUpTo(app.steppers["preferences.people"])
        app.swipeDown()
        try capture("07-preferences")

        // Settings: profile and offer alerts.
        app.openTab("Settings")
        XCTAssertTrue(app.element(withID: "profile.spent").waitForExistence(timeout: 5))
        try capture("08-settings")
    }

    private func capture(_ name: String) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appending(path: "\(name).png"))
    }
}
