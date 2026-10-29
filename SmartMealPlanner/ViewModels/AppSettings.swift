//
//  AppSettings.swift
//  SmartMealPlanner
//
//  App-wide settings shown on the Settings screen.
//

import Foundation
import SwiftUI

/// The app's light / dark theme choice.
enum AppAppearance: String, CaseIterable, Identifiable {
    /// Follow the device setting.
    case system
    case light
    case dark

    /// UserDefaults key the choice is stored under (read with `@AppStorage`).
    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Passed to `.preferredColorScheme`; nil lets the device decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppVersion {
    /// "1.0 (1)" from the bundle's marketing version and build number.
    static func displayString(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String
        let build = infoDictionary?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (nil, build?):
            return build
        case (nil, nil):
            return "Unknown"
        }
    }
}

/// Launch arguments the UI tests use to start the app in a known state.
/// What "Share Smart Meal Planner" sends.
enum AppSharing {
    /// The project page until the app is on the App Store; then its App Store link.
    static let url = URL(string: "https://github.com/nivedhitha97/SmartMealPlanner")!
    static let message = "I plan my week's meals and groceries with Smart Meal Planner: recipes for my diet, "
        + "this week's supermarket offers and one grocery list. Try it:"
}

enum LaunchArguments {
    /// Wipe saved preferences, routine, plan and settings before the app starts.
    static let resetState = "-uiTestingResetState"
    /// Skip the splash screen.
    static let skipSplash = "-uiTestingSkipSplash"
    /// Followed by a number of seconds: keep the splash up that long, so a UI test can see it.
    static let splashSeconds = "-uiTestingSplashSeconds"
    /// Use the UI tests' fixed offers and recipes (Data/UITestOffers.json, UITestRecipes.json) instead of the network,
    /// so results don't depend on it. Only UI tests pass this; users never see that data.
    static let bundledData = "-uiTestingBundledData"
    /// Followed by a number of seconds: wait that long before looking up a typed postcode, so a UI test can
    /// save while the lookup is still running without the nearby-stores list appearing mid-scroll.
    static let postcodeLookupSeconds = "-uiTestingPostcodeLookupSeconds"

    static let defaultSplashSeconds = 1.4
    /// The pause after the last keystroke before a postcode is looked up.
    static let defaultPostcodeLookupSeconds = 0.4

    static func contains(_ argument: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(argument)
    }

    /// How long the splash screen stays up.
    static func splashDuration(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Double {
        seconds(after: splashSeconds, in: arguments) ?? defaultSplashSeconds
    }

    /// How long to wait before looking up a typed postcode.
    static func postcodeLookupDelay(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Double {
        seconds(after: postcodeLookupSeconds, in: arguments) ?? defaultPostcodeLookupSeconds
    }

    /// The non-negative number following `flag`, if there is one.
    private static func seconds(after flag: String, in arguments: [String]) -> Double? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]), seconds >= 0 else {
            return nil
        }
        return seconds
    }
}
