//
//  MainTabView.swift
//  SmartMealPlanner
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            WeeklyPlanView()
                .tabItem {
                    Label("Plan", systemImage: "calendar")
                }
            WeeklyOffersView()
                .tabItem {
                    Label("Offers", systemImage: "tag")
                }
            PreferencesView()
                .tabItem {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.brandPrimary)
    }
}

#Preview {
    MainTabView()
        .environmentObject(PlanningViewModel(ai: LocalHeuristicAIPlanner()))
}
