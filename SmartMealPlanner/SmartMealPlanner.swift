//
//  SmartMealPlannerApp.swift
//  SmartMealPlanner
//
//  Created by Nivedhitha on 29/12/2025.
//

import SwiftUI
import UserNotifications

@main
struct SmartMealPlannerApp: App {

    @StateObject private var planning: PlanningViewModel
    @StateObject private var shopping = ShoppingListStore()
    @State private var showSplash: Bool
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    init() {
        // UI tests start from a clean slate so each test is independent of earlier runs.
        if LaunchArguments.contains(LaunchArguments.resetState), let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        _planning = StateObject(wrappedValue: PlanningViewModel(ai: LocalHeuristicAIPlanner()))
        _showSplash = State(initialValue: !LaunchArguments.contains(LaunchArguments.skipSplash))
        UNUserNotificationCenter.current().delegate = OfferAlertDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                    .environmentObject(planning)
                    .environmentObject(shopping)
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .task {
                guard showSplash else { return }
                try? await Task.sleep(for: .seconds(LaunchArguments.splashDuration()))
                withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
            }
        }
    }
}
