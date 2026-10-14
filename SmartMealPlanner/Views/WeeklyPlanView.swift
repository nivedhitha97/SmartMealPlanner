//
//  WeeklyPlanView.swift
//  SmartMealPlanner
//

import SwiftUI

struct WeeklyPlanView: View {

    @EnvironmentObject private var planning: PlanningViewModel

    @State private var selectedDayIndex = 0
    @State private var groceryChecklist = GroceryChecklist()
    @State private var showAllGroceries = false

    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let rangeFormatter: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateTemplate = "MMMd"
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if planning.isLoading {
                    loadingState
                } else if let plan = planning.suggestedPlan {
                    planScroll(plan)
                } else {
                    PlanEmptyState(isLoading: planning.isLoading) {
                        Task { await planning.generatePlan() }
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Your week")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if let message = planning.lastError {
                    errorBanner(message)
                }
            }
            .onChange(of: planning.suggestedPlan?.id) {
                selectedDayIndex = WeeklyPlanContent.initialDayIndex(in: planning.suggestedPlan?.weeklyMealPlan)
                groceryChecklist.reset()
                showAllGroceries = false
            }
            .onAppear {
                selectedDayIndex = WeeklyPlanContent.initialDayIndex(in: planning.suggestedPlan?.weeklyMealPlan)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.brandPrimary)
            Text("Building your 7-day plan\nand grocery list…")
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accentCoral)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.accentCoralSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Plan

    @ViewBuilder
    private func planScroll(_ plan: AISuggestedWeekPlan) -> some View {
        let breakfastPref = UserPreferences.loadFromUserDefaults()?.breakfastRecipePreference ?? .includeRecipes
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenHeader(eyebrow: weekRange(plan.weeklyMealPlan), title: "Your week") {
                    planMenu
                }

                budgetCard(plan)

                notesCard(plan)

                mealsSection(plan.weeklyMealPlan, breakfastPreference: breakfastPref)

                nutritionSection(plan.weeklyMealPlan)

                grocerySection(plan)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var planMenu: some View {
        Menu {
            Button {
                Task { await planning.generatePlan() }
            } label: {
                Label("Regenerate plan", systemImage: "sparkles")
            }
            Button(role: .destructive) {
                planning.clearPlan()
            } label: {
                Label("Clear plan", systemImage: "trash")
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.brandPrimary, in: Circle())
        }
        .disabled(planning.isLoading)
        .accessibilityLabel("Plan actions")
    }

    private func budgetCard(_ plan: AISuggestedWeekPlan) -> some View {
        let budget = BudgetSummary(plan: plan)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Estimated groceries")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: budget.isWithinBudget ? "checkmark" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(budget.statusText)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(budget.isWithinBudget ? Color.white.opacity(0.18) : Color.accentCoral, in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(plan.estimatedGroceryTotal.euros)
                    .font(.system(size: 40, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                Text("of \(plan.budgetWeekly.eurosRounded) budget")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule()
                        .fill(budget.isWithinBudget ? Color.white : Color.accentCoral)
                        .frame(width: geo.size.width * budget.progress)
                }
            }
            .frame(height: 8)

            Text(budget.remainingText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func notesCard(_ plan: AISuggestedWeekPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconCircle(systemName: "sparkles", tint: .accentCoral, background: .accentCoralSoft)
                Text("Planner notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            Text(plan.aiSummary)
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !plan.offerHighlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(plan.offerHighlights, id: \.self) { line in
                        Badge(text: line, systemImage: "tag.fill", foreground: .accentCoral, background: .accentCoralSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Meals

    private func mealsSection(_ weekly: WeeklyMealPlan, breakfastPreference: BreakfastRecipePreference) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Meals", subtitle: "Tap a dish for the recipe, video and cookbook")

            HStack(spacing: 6) {
                ForEach(Array(weekly.days.enumerated()), id: \.element.id) { index, day in
                    dayPill(day.date, isSelected: index == selectedDayIndex)
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.25)) { selectedDayIndex = index }
                        }
                        .accessibilityIdentifier("plan.day.\(index)")
                }
            }

            if weekly.days.indices.contains(selectedDayIndex) {
                let day = weekly.days[selectedDayIndex]
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(Self.dayTitleFormatter.string(from: day.date))
                            .font(.cardTitle)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(WeeklyPlanContent.homeMealsText(for: day))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(day.mealsWithSlot.enumerated()), id: \.element.0) { index, pair in
                        if index > 0 { RowDivider() }
                        mealSlotRow(slot: pair.0, recipe: pair.1, breakfastPreference: breakfastPreference)
                    }
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.borderSubtle))
                .id(day.id)
                .transition(.opacity)
            }
        }
    }

    private func dayPill(_ date: Date, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color.textSecondary)
            Text(date, format: .dateTime.day())
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(isSelected ? Color.brandPrimary : Color.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Color.clear : Color.borderSubtle)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func mealSlotRow(slot: MealSlot, recipe: Recipe?, breakfastPreference: BreakfastRecipePreference) -> some View {
        let style = SlotStyle(slot)
        if let recipe {
            NavigationLink {
                RecipeDetailView(recipe: recipe, slot: slot)
            } label: {
                HStack(spacing: 14) {
                    RecipeImage(url: recipe.imageURLParsed, placeholderKey: recipe.name)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        slotLabel(slot.rawValue, style: style)
                        Text(recipe.name)
                            .font(.cardTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(recipe.cuisine)
                            if recipe.youtubeURL != nil || recipe.cookbookURL != nil {
                                Text("·").foregroundStyle(Color.textTertiary)
                                Label("Video & book", systemImage: "link")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.meal.\(slot.rawValue)")
        } else {
            let isGranola = WeeklyPlanContent.isGranolaSlot(slot, breakfastPreference)
            HStack(spacing: 14) {
                Image(systemName: isGranola ? "cup.and.saucer.fill" : "fork.knife")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 64, height: 64)
                    .background(Color.bgMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    slotLabel(slot.rawValue, style: .muted)
                    Text(WeeklyPlanContent.emptySlotTitle(slot: slot, breakfastPreference: breakfastPreference))
                        .font(.cardTitle)
                        .foregroundStyle(Color.textSecondary)
                    Text(WeeklyPlanContent.emptySlotDetail(slot: slot, breakfastPreference: breakfastPreference))
                        .font(.footnote)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
    }

    private func slotLabel(_ text: String, style: SlotStyle) -> some View {
        HStack(spacing: 5) {
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .bold))
            Text(text.uppercased())
                .font(.eyebrow)
                .tracking(0.6)
        }
        .foregroundStyle(style.tint)
    }

    // MARK: - Nutrition

    private func nutritionSection(_ weekly: WeeklyMealPlan) -> some View {
        let totals = NutritionTotals.aggregate(recipes: weekly.allPlannedRecipes)
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Nutrition this week", subtitle: "Approximate, across all home-cooked meals")
            LazyVGrid(columns: columns, spacing: 12) {
                statTile(icon: "flame.fill", tint: .accentCoral, background: .accentCoralSoft, value: totals.calories, unit: "", label: "kcal")
                statTile(icon: "bolt.fill", tint: .brandPrimary, background: .brandPrimarySoft, value: totals.protein, unit: " g", label: "Protein")
                statTile(icon: "leaf.fill", tint: .accentAmber, background: .accentAmberSoft, value: totals.carbs, unit: " g", label: "Carbs")
                statTile(icon: "drop.fill", tint: .textSecondary, background: .bgMuted, value: totals.fat, unit: " g", label: "Fat")
            }
        }
    }

    private func statTile(icon: String, tint: Color, background: Color, value: Double, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted(.number.precision(.fractionLength(0))) + unit)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.textPrimary)
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Groceries

    private func grocerySection(_ plan: AISuggestedWeekPlan) -> some View {
        let lines = WeeklyPlanContent.visibleGroceryLines(plan.groceryLines, showAll: showAllGroceries)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Grocery list") {
                Text("\(plan.groceryLines.count) items")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { RowDivider() }
                    groceryRow(line)
                }
                if WeeklyPlanContent.canExpandGroceries(plan.groceryLines) {
                    RowDivider()
                    Button {
                        withAnimation(.snappy) { showAllGroceries.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showAllGroceries ? "Show less" : "Show all \(plan.groceryLines.count) items")
                            Image(systemName: showAllGroceries ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.borderSubtle))
        }
    }

    private func groceryRow(_ line: GroceryLineItem) -> some View {
        let isChecked = groceryChecklist.isChecked(line)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { groceryChecklist.toggle(line) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isChecked ? Color.clear : Color.borderSubtle, lineWidth: 1.5)
                        .background(Circle().fill(isChecked ? Color.brandPrimary : Color.clear))
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(line.ingredientName)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(isChecked)
                        .foregroundStyle(isChecked ? Color.textTertiary : Color.textPrimary)
                    HStack(spacing: 6) {
                        Text("\(Int(line.totalGrams)) g")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                        if let offer = line.matchedOffer {
                            Badge(text: offer.storeName, systemImage: "tag.fill", foreground: .brandPrimaryDeep, background: .brandPrimarySoft)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(line.estimatedLinePrice.euros)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isChecked ? Color.textTertiary : Color.textPrimary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(line.rationale)
    }

    // MARK: - Helpers

    private func weekRange(_ weekly: WeeklyMealPlan) -> String? {
        guard let first = weekly.days.first?.date, let last = weekly.days.last?.date else { return nil }
        return Self.rangeFormatter.string(from: first, to: last)
    }

}

// MARK: - Slot styling

struct SlotStyle {
    let icon: String
    let tint: Color

    init(icon: String, tint: Color) {
        self.icon = icon
        self.tint = tint
    }

    init(_ slot: MealSlot) {
        switch slot {
        case .breakfast: self.init(icon: "sun.max.fill", tint: .accentAmber)
        case .lunch: self.init(icon: "fork.knife", tint: .brandPrimary)
        case .dinner: self.init(icon: "moon.fill", tint: .accentCoral)
        }
    }

    static let muted = SlotStyle(icon: "clock", tint: .textTertiary)
}

// MARK: - Empty state

private struct PlanEmptyState: View {
    let isLoading: Bool
    let onGenerate: () -> Void

    @State private var hasPreferences = false
    @State private var hasRoutine = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ScreenHeader(eyebrow: "This week", title: "Your week")

                illustration

                VStack(spacing: 8) {
                    Text("Plan your week in seconds")
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)
                    Text("We’ll build 7 days of meals and a grocery list that fits your diet, routine and budget.")
                        .font(.callout)
                        .lineSpacing(3)
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.center)

                VStack(spacing: 0) {
                    step(1, "Set your preferences", "Diet, cuisines, budget", done: hasPreferences)
                    RowDivider()
                    step(2, "Choose a meal routine", "Preferences → Meal routine", done: hasRoutine)
                    RowDivider()
                    step(3, "Generate your plan", "Recipes + grocery list", done: false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.borderSubtle))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button(action: onGenerate) {
                Label("Generate my week", systemImage: "sparkles")
            }
            .buttonStyle(.primary)
            .disabled(isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .floatingBarBackground()
        }
        .onAppear {
            hasPreferences = UserPreferences.loadFromUserDefaults() != nil
            hasRoutine = MealRoutine.load() != nil
        }
    }

    private var illustration: some View {
        ZStack {
            IconCircle(systemName: "calendar", tint: .brandPrimary, background: .brandPrimarySoft, size: 150)
            IconCircle(systemName: "sun.max.fill", tint: .accentAmber, background: .accentAmberSoft, size: 52)
                .offset(x: -84, y: 50)
            IconCircle(systemName: "fork.knife", tint: .accentCoral, background: .accentCoralSoft, size: 56)
                .offset(x: 78, y: -56)
        }
        .frame(height: 170)
        .accessibilityHidden(true)
    }

    private func step(_ number: Int, _ title: String, _ subtitle: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.brandPrimary : Color.bgMuted)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.footnote.bold())
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(done ? Color.textSecondary : Color.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    WeeklyPlanView()
        .environmentObject(PlanningViewModel(ai: LocalHeuristicAIPlanner()))
}
