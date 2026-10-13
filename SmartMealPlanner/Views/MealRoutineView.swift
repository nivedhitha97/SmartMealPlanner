//
//  MealRoutineView.swift
//  SmartMealPlanner
//
//  Created by Nivedhitha on 30/12/2025.
//

import SwiftUI

struct MealRoutineView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var breakfast = MealRoutine.default.breakfastType
    @State private var lunch = MealRoutine.default.lunchType
    @State private var dinner = MealRoutine.default.dinnerType

    private func loadRoutine() {
        guard let saved = MealRoutine.load() else { return }

        breakfast = saved.breakfastType
        lunch = saved.lunchType
        dinner = saved.dinnerType
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Meal routine", subtitle: "Tell us how each meal usually happens. Only home-cooked meals get recipes.")
                    .padding(.bottom, 8)

                mealCard("Breakfast", slot: .breakfast, selection: $breakfast)
                mealCard("Lunch", slot: .lunch, selection: $lunch)
                mealCard("Dinner", slot: .dinner, selection: $dinner)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button("Save routine", action: saveRoutine)
                .buttonStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .floatingBarBackground()
        }
        .screenBackground()
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadRoutine()
        }
    }

    private func mealCard(_ title: String, slot: MealSlot, selection: Binding<MealType>) -> some View {
        let style = SlotStyle(slot)
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: style.icon, tint: style.tint, tintBackground: style.tint.opacity(0.14), title: title) {
                Text(selection.wrappedValue.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color.bgMuted, in: Capsule())
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MealType.allCases) { type in
                    OptionTile(type: type, isSelected: selection.wrappedValue == type) {
                        withAnimation(.snappy(duration: 0.2)) { selection.wrappedValue = type }
                    }
                }
            }
        }
        .card()
    }

    func saveRoutine() {
        let routine = MealRoutine(
            breakfastType: breakfast,
            lunchType: lunch,
            dinnerType: dinner
        )

        if routine.save() {
            dismiss()
        }
    }
}

/// Matches the Figma "OptionTile" component (Type × Selected).
private struct OptionTile: View {
    let type: MealType
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch type {
        case .fixed: return "repeat"
        case .flexible: return "shuffle"
        case .homeCooked: return "frying.pan"
        case .outside: return "fork.knife"
        }
    }

    private var detail: String {
        switch type {
        case .fixed: return "Same meal daily"
        case .flexible: return "Mix it up"
        case .homeCooked: return "Recipe from plan"
        case .outside: return "Eat out / canteen"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
                    Spacer()
                    SelectionIndicator(isSelected: isSelected, size: 20)
                }
                Text(type.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.brandPrimaryDeep : Color.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.brandPrimarySoft : Color.bgCanvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPrimary : Color.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        MealRoutineView()
    }
}
