//
//  SettingsUITests.swift
//  SmartMealPlannerUITests
//
//  Settings screen: light / dark theme and version number.
//

import XCTest

@MainActor
final class SettingsUITests: XCTestCase {

    /// A spot on the Settings screen below the cards, where only the screen background shows.
    private let backgroundPoint = CGPoint(x: 12, y: 600)

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testVersionNumberIsShown() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Settings")

        let version = app.element(withID: "settings.version")
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        XCTAssertNotNil(version.label.range(of: #"Version.*\d+\.\d+"#, options: .regularExpression),
                        "Expected a version like “1.0 (1)”, got “\(version.label)”")
    }

    func testSystemIsTheDefaultAppearance() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Settings")

        XCTAssertTrue(app.buttons["settings.appearance.system"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected)
        XCTAssertFalse(app.buttons["settings.appearance.dark"].isSelected)
    }

    func testChoosingDarkOrLightChangesTheTheme() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Settings")

        app.buttons["settings.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        XCTAssertLessThan(luminanceAfterSettling(app), 0.3, "Background should be dark")

        app.buttons["settings.appearance.light"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.light"].isSelected)
        XCTAssertGreaterThan(luminanceAfterSettling(app), 0.7, "Background should be light")
    }

    func testThemeChoiceIsRememberedAfterRelaunch() {
        var app = XCUIApplication.launchForTesting()
        app.openTab("Settings")
        app.buttons["settings.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        app.terminate()

        app = XCUIApplication.launchForTesting(resetState: false)
        app.openTab("Settings")

        XCTAssertTrue(app.buttons["settings.appearance.dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        XCTAssertLessThan(luminanceAfterSettling(app), 0.3, "Dark theme should apply on launch")
    }

    func testDarkThemeAppliesToOtherScreens() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Settings")
        app.buttons["settings.appearance.dark"].tap()

        app.openTab("Offers")
        XCTAssertTrue(app.staticTexts["Deals near you"].waitForExistence(timeout: 5))
        // Left margin next to the offer cards is plain background.
        XCTAssertLessThan(luminanceAfterSettling(app, at: CGPoint(x: 6, y: 400)), 0.3)
    }

    private func luminanceAfterSettling(_ app: XCUIApplication, at point: CGPoint? = nil) -> CGFloat {
        // Let the theme transition finish before sampling the screen.
        _ = app.wait(for: .runningForeground, timeout: 1)
        Thread.sleep(forTimeInterval: 0.6)
        return app.screenLuminance(at: point ?? backgroundPoint)
    }

    func testOfferAlertsCanBeTurnedOnPerStore() {
        let app = XCUIApplication.launchForTesting()
        app.openTab("Settings")
        let toggle = app.switches["settings.offerAlerts"]
        app.scrollTo(toggle)
        toggle.switches.firstMatch.tap()

        // iOS asks for permission the first time; allow it (in the test simulator).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        let jumbo = app.switches["settings.offerAlerts.jumbo"]
        XCTAssertTrue(jumbo.waitForExistence(timeout: 5), "A switch per store with offers")
        XCTAssertTrue(app.element(containing: "Every Wednesday").exists, "Jumbo's alert day")
    }
}
