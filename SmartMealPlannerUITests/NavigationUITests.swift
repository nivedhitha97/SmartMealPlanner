//
//  NavigationUITests.swift
//  SmartMealPlannerUITests
//
//  Launch, splash screen and moving between tabs.
//

import XCTest

@MainActor
final class NavigationUITests: XCTestCase {

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testSplashScreenShowsThenGivesWayToThePlanTab() {
        // XCUITest only starts looking a few seconds after launch, so hold the splash for longer than usual.
        let app = XCUIApplication.launchForTesting(skipSplash: false, extraArguments: [LaunchFlag.splashSeconds, "8"])

        let splash = app.element(withID: "splash")
        XCTAssertTrue(splash.waitForExistence(timeout: 5), "Splash screen should show on launch")
        XCTAssertTrue(splash.label.contains("Smart Meal Planner"))

        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: splash)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 15), .completed, "Splash screen should go away")
        XCTAssertTrue(app.staticTexts["Your week"].waitForExistence(timeout: 5))
    }

    func testEveryTabOpensItsScreen() {
        let app = XCUIApplication.launchForTesting()

        let screens = [
            ("Offers", "Deals near you"),
            ("List", "Grocery list"),
            ("Preferences", "These shape your weekly plan and grocery list."),
            ("Settings", "Appearance"),
            ("Plan", "Your week"),
        ]
        for (tab, text) in screens {
            app.openTab(tab)
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5), "\(tab) tab should show “\(text)”")
        }
    }
}
