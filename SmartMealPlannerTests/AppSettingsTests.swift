//
//  AppSettingsTests.swift
//  SmartMealPlannerTests
//
//  Logic behind the Settings screen: appearance choice and version number.
//

import SwiftUI
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Settings screen")
struct AppSettingsTests {

    @Test func appearanceOptionsAreSystemLightAndDarkInThatOrder() {
        #expect(AppAppearance.allCases.map(\.title) == ["System", "Light", "Dark"])
    }

    @Test func eachAppearanceMapsToTheRightColorScheme() {
        #expect(AppAppearance.system.colorScheme == nil, "System follows the device")
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test(arguments: AppAppearance.allCases)
    func appearanceIsStoredByItsRawValue(appearance: AppAppearance) {
        #expect(AppAppearance(rawValue: appearance.rawValue) == appearance)
    }

    @Test func unknownStoredAppearanceIsRejected() {
        #expect(AppAppearance(rawValue: "sepia") == nil)
    }

    @Test(arguments: [
        (["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"], "1.0 (1)"),
        (["CFBundleShortVersionString": "2.3.1", "CFBundleVersion": "45"], "2.3.1 (45)"),
        (["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1.0"], "1.0"),
        (["CFBundleShortVersionString": "1.0"], "1.0"),
        (["CFBundleVersion": "7"], "7"),
        ([:], "Unknown"),
    ] as [([String: String], String)])
    func versionShowsMarketingVersionAndBuild(info: [String: String], expected: String) {
        #expect(AppVersion.displayString(infoDictionary: info) == expected)
    }

    @Test func versionReadsTheAppBundle() {
        let version = AppVersion.displayString()

        #expect(version != "Unknown")
        #expect(version.first?.isNumber == true)
    }

    @Test(arguments: [
        ([], 1.4),
        (["-uiTestingSplashSeconds", "8"], 8.0),
        (["-uiTestingSplashSeconds", "0"], 0.0),
        (["-uiTestingSplashSeconds"], 1.4),
        (["-uiTestingSplashSeconds", "soon"], 1.4),
        (["-uiTestingSplashSeconds", "-3"], 1.4),
    ] as [([String], Double)])
    func splashDurationCanBeOverriddenForUITests(arguments: [String], expected: Double) {
        #expect(LaunchArguments.splashDuration(in: arguments) == expected)
    }

    @Test func launchFlagsAreDetected() {
        let arguments = ["SmartMealPlanner", LaunchArguments.skipSplash]

        #expect(LaunchArguments.contains(LaunchArguments.skipSplash, in: arguments))
        #expect(!LaunchArguments.contains(LaunchArguments.resetState, in: arguments))
    }
}
