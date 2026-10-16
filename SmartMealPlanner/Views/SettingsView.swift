//
//  SettingsView.swift
//  SmartMealPlanner
//

import SwiftUI

struct SettingsView: View {

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @EnvironmentObject private var shopping: ShoppingListStore

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
                    appearanceCard
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
