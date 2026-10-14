//
//  SettingsView.swift
//  SmartMealPlanner
//

import SwiftUI

struct SettingsView: View {

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Settings")
                        .padding(.bottom, 8)

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
}
