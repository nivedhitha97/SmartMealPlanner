//
//  MainTabView.swift
//  SmartMealPlanner
//

import SwiftUI

enum AppTab: Hashable {
    case plan, offers, list, preferences, settings
}

extension EnvironmentValues {
    /// Switches to another tab, e.g. from the Plan screen's grocery card to the List tab.
    @Entry var openTab: (AppTab) -> Void = { _ in }
}

struct MainTabView: View {
    @EnvironmentObject private var planning: PlanningViewModel
    @EnvironmentObject private var shopping: ShoppingListStore

    @State private var selection: AppTab = .plan

    var body: some View {
        TabView(selection: $selection) {
            Tab("Plan", systemImage: "calendar", value: .plan) {
                WeeklyPlanView()
            }
            Tab("Offers", systemImage: "tag", value: .offers) {
                WeeklyOffersView()
            }
            Tab("List", systemImage: "checklist", value: .list) {
                GroceryListView()
            }
            .badge(shopping.list.itemsLeft)
            Tab("Preferences", systemImage: "slider.horizontal.3", value: .preferences) {
                PreferencesView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tint(.brandPrimary)
        .environment(\.openTab) { selection = $0 }
        // The plan's grocery lines go on the shopping list; a new plan replaces them, added items stay.
        .onAppear { shopping.change { $0.syncPlan(planning.suggestedPlan) } }
        .onChange(of: planning.suggestedPlan?.id) {
            shopping.change { $0.syncPlan(planning.suggestedPlan) }
        }
        // Keep the weekly offer alerts in step with the stores' current update days.
        .task {
            let scheduler = OfferAlertScheduler.shared
            guard scheduler.isEnabled else { return }
            let live = await GroceryDataServices.shared.latest().stores
            let stores = live.isEmpty ? GroceryDataServices.defaultStoreSchedules : live
            await scheduler.reschedule(stores: stores, nearbyChains: UserPreferences.loadFromUserDefaults()?.nearbyChains)
        }
        // Tapping an offer alert opens the Offers tab.
        .onReceive(NotificationCenter.default.publisher(for: OfferAlertDelegate.openOffers)) { _ in
            selection = .offers
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(PlanningViewModel(ai: LocalHeuristicAIPlanner()))
        .environmentObject(ShoppingListStore())
}
