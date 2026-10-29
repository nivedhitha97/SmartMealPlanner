//
//  SettingsView.swift
//  SmartMealPlanner
//

import SwiftUI
import UIKit

struct SettingsView: View {

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @EnvironmentObject private var shopping: ShoppingListStore
    @Environment(\.openURL) private var openURL

    @State private var alertsEnabled = OfferAlertScheduler.shared.isEnabled
    @State private var alertStoreIDs: Set<String> = []
    @State private var storeSchedules: [StoreSchedule] = []
    @State private var notificationsDenied = false

    private static let weekFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "dMMM"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Settings")
                        .padding(.bottom, 8)

                    profileCard
                    offerAlertsCard
                    appearanceCard
                    shareCard
                    LegalCard()
                    aboutCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadStoreSchedules() }
        }
    }

    // MARK: - Profile

    /// This week's spending (items ticked off in the grocery list) against the weekly budget, and recent weeks.
    private var profileCard: some View {
        let budget = UserPreferences.loadFromUserDefaults()?.budgetWeekly ?? 50
        let weeks = shopping.list.weeklySpending(budget: budget)
        return VStack(alignment: .leading, spacing: 16) {
            CardHeader(icon: "person.crop.circle.fill", tint: .brandPrimary, tintBackground: .brandPrimarySoft,
                       title: "Profile", subtitle: "Spending from items ticked off in your grocery list")
            if let thisWeek = weeks.first {
                thisWeekSummary(thisWeek)
            }
            if weeks.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(weeks.dropFirst())) { week in
                        RowDivider()
                        pastWeekRow(week)
                    }
                }
            }
        }
        .card()
    }

    private func thisWeekSummary(_ week: WeekSpending) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent this week")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(week.spent.euros)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityIdentifier("profile.spent")
                }
                Spacer()
                Text("of \(week.budget.eurosRounded)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }
            ProgressView(value: week.progress)
                .tint(week.isOverBudget ? Color.accentCoral : Color.brandPrimary)
            if week.purchaseCount > 0 {
                HStack(spacing: 8) {
                Badge(text: week.isOverBudget
                        ? "\((-week.savedAgainstBudget).euros) over budget"
                        : "Saved \(week.savedAgainstBudget.euros) against your budget",
                      systemImage: week.isOverBudget ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                      foreground: week.isOverBudget ? .accentCoral : .brandPrimaryDeep,
                      background: week.isOverBudget ? .accentCoralSoft : .brandPrimarySoft)
                    .accessibilityIdentifier("profile.saved")
                if week.offerSavings > 0 {
                    Badge(text: "\(week.offerSavings.euros) from offers", systemImage: "tag.fill",
                          foreground: .accentAmber, background: .accentAmberSoft)
                }
                }
            } else {
                Text("Tick items off in your grocery list as you buy them to track your spending.")
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    private func pastWeekRow(_ week: WeekSpending) -> some View {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: week.weekStart) ?? week.weekStart
        return HStack {
            Text(Self.weekFormatter.string(from: week.weekStart, to: end))
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(week.spent.euros)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(week.purchaseCount == 0 ? "Nothing ticked off"
                     : week.isOverBudget ? "\((-week.savedAgainstBudget).euros) over"
                     : "Saved \(week.savedAgainstBudget.euros)")
                    .font(.caption)
                    .foregroundStyle(week.isOverBudget ? Color.accentCoral : Color.textSecondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Offer alerts

    private var offerStores: [StoreSchedule] {
        storeSchedules.filter(\.fetchesOffers).sorted { $0.name < $1.name }
    }

    /// A weekly notification on each chosen store's update day, when its new offers are in.
    private var offerAlertsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "bell.badge.fill", tint: .accentAmber, tintBackground: .accentAmberSoft,
                       title: "Offer alerts", subtitle: "When a store's new offers are in")
            Toggle("Notify me", isOn: Binding(get: { alertsEnabled }, set: { setAlerts($0) }))
                .font(.subheadline.weight(.medium))
                .tint(.brandPrimary)
                .accessibilityIdentifier("settings.offerAlerts")
            if notificationsDenied {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications are turned off for Smart Meal Planner in iOS Settings.")
                        .font(.footnote)
                        .foregroundStyle(Color.accentCoral)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            if alertsEnabled {
                VStack(spacing: 0) {
                    ForEach(offerStores) { store in
                        RowDivider()
                        Toggle(isOn: Binding(get: { alertStoreIDs.contains(store.id) },
                                             set: { setAlert($0, for: store) })) {
                            HStack(spacing: 10) {
                                StoreBadge(store: store.name, size: 24)
                                    .frame(width: StoreBadge.columnWidth(size: 24), alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(store.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Every \(store.updateDay) at \(OfferAlert.hour):00")
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .tint(.brandPrimary)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("settings.offerAlerts.\(store.id)")
                    }
                }
            }
        }
        .card()
    }

    private func loadStoreSchedules() async {
        let live = await GroceryDataServices.shared.latest().stores
        storeSchedules = live.isEmpty ? GroceryDataServices.defaultStoreSchedules : live
        alertStoreIDs = OfferAlertScheduler.shared.storeIDs(for: storeSchedules, nearbyChains: nearbyChains)
    }

    private var nearbyChains: Set<String>? { UserPreferences.loadFromUserDefaults()?.nearbyChains }

    private func setAlerts(_ on: Bool) {
        Task {
            let scheduler = OfferAlertScheduler.shared
            if on {
                let granted = await scheduler.requestPermission()
                notificationsDenied = !granted
                guard granted else { alertsEnabled = false; return }
            }
            alertsEnabled = on
            scheduler.isEnabled = on
            await scheduler.reschedule(stores: storeSchedules, nearbyChains: nearbyChains)
        }
    }

    private func setAlert(_ on: Bool, for store: StoreSchedule) {
        if on { alertStoreIDs.insert(store.id) } else { alertStoreIDs.remove(store.id) }
        let scheduler = OfferAlertScheduler.shared
        scheduler.chosenStoreIDs = alertStoreIDs
        Task { await scheduler.reschedule(stores: storeSchedules, nearbyChains: nearbyChains) }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "paintpalette.fill", tint: .accentCoral, tintBackground: .accentCoralSoft,
                       title: "Appearance", subtitle: "Choose a light or dark theme")
            HStack(spacing: 10) {
                ForEach(AppAppearance.allCases) { option in
                    appearanceOption(option)
                }
            }
        }
        .card()
    }

    private func appearanceOption(_ option: AppAppearance) -> some View {
        let isSelected = appearance == option
        return Button {
            withAnimation(.snappy(duration: 0.2)) { appearance = option }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.brandPrimaryDeep : Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? Color.brandPrimarySoft : Color.bgCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPrimary : Color.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(option.rawValue)")
    }

    /// Sends the app's link with the iOS share sheet.
    private var shareCard: some View {
        ShareLink(item: AppSharing.url, subject: Text("Smart Meal Planner"), message: Text(AppSharing.message)) {
            HStack(spacing: 12) {
                IconTile(systemName: "square.and.arrow.up.fill", tint: .brandPrimary, background: .brandPrimarySoft)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Share Smart Meal Planner")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Send the app to friends and family")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.share")
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "info.circle.fill", tint: .brandPrimary, tintBackground: .brandPrimarySoft, title: "About")
            HStack {
                Text("Version")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(AppVersion.displayString())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.version")
        }
        .card()
    }
}

#Preview {
    SettingsView()
        .environmentObject(ShoppingListStore())
}
