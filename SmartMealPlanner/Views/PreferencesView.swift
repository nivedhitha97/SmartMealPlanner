//
//  PreferencesView.swift
//  SmartMealPlanner
//

import SwiftUI

struct PreferencesView: View {

    @State private var form = PreferencesForm()
    @State private var location: PostcodeLocation?
    @State private var isLookingUpPostcode = false
    @State private var postcodeError: String?
    @State private var routineSummary: String?
    @State private var didSave = false
    /// Saved preferences are loaded once; later appearances (e.g. back from Meal routine) keep unsaved edits.
    @State private var hasLoaded = false
    @State private var savedWhileLookingUp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Preferences", subtitle: "These shape your weekly plan and grocery list.")
                        .padding(.bottom, 8)

                    dietCard
                    peopleCard
                    breakfastCard
                    cuisinesCard
                    discoveryCard
                    exclusionsCard
                    budgetCard
                    routineLink

                    Button(action: savePreferences) {
                        Label(didSave ? "Saved" : "Save preferences", systemImage: didSave ? "checkmark" : "tray.and.arrow.down")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.primary)
                    .disabled(postcodeError != nil)
                    .accessibilityIdentifier("preferences.save")
                    .sensoryFeedback(.success, trigger: didSave) { _, new in new }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Preferences")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if !hasLoaded {
                    loadPreferences()
                    hasLoaded = true
                }
                loadRoutineSummary()
            }
        }
    }

    // MARK: - Cards

    private var dietCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "leaf.fill", tint: .brandPrimary, tintBackground: .brandPrimarySoft, title: "Diet", subtitle: "What do you eat?")
            FlowLayout {
                ForEach(PreferencesForm.dietOptions, id: \.self) { option in
                    Chip(title: option, isSelected: form.dietType == option) {
                        form.dietType = option
                    }
                }
            }
        }
        .card()
    }

    private var breakfastCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "cup.and.saucer.fill", tint: .accentAmber, tintBackground: .accentAmberSoft, title: "Breakfast", subtitle: "How breakfast appears in your plan")
            breakfastOption(.includeRecipes, title: "Include breakfast recipes", subtitle: "Pick from the recipe catalog")
            breakfastOption(.granolaMuesliOnly, title: "Granola / muesli only", subtitle: "No cooked breakfast; lunch & dinner still follow your routine")
        }
        .card()
    }

    private func breakfastOption(_ mode: BreakfastRecipePreference, title: String, subtitle: String) -> some View {
        let isSelected = form.breakfastRecipePreference == mode
        return Button {
            withAnimation(.snappy(duration: 0.2)) { form.breakfastRecipePreference = mode }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.brandPrimaryDeep : Color.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                SelectionIndicator(isSelected: isSelected)
            }
            .padding(14)
            .background(isSelected ? Color.brandPrimarySoft : Color.bgCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPrimary : Color.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var peopleCard: some View {
        HStack(spacing: 12) {
            CardHeader(icon: "person.2.fill", tint: .accentCoral, tintBackground: .accentCoralSoft,
                       title: "People", subtitle: "Scales recipes and groceries")
            Stepper(value: $form.people, in: UserPreferences.peopleRange) {
                Text("\(form.people)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText(value: Double(form.people)))
                    .animation(.snappy, value: form.people)
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .fixedSize()
            .accessibilityLabel("People")
            .accessibilityValue("\(form.people)")
            .accessibilityIdentifier("preferences.people")
        }
        .card()
    }

    private var cuisinesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "globe.europe.africa.fill", tint: .accentCoral, tintBackground: .accentCoralSoft, title: "Cuisines", subtitle: "Pick as many as you like")
            FlowLayout {
                ForEach(PreferencesForm.cuisineOptions, id: \.self) { cuisine in
                    Chip(title: cuisine, isSelected: form.selectedCuisines.contains(cuisine)) {
                        form.toggleCuisine(cuisine)
                    }
                }
            }
        }
        .card()
    }

    /// Recipes written by Apple's on-device AI for these preferences.
    private var discoveryCard: some View {
        let availability = RecipeDiscovery.shared.availability
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $form.discoverRecipes) {
                CardHeader(icon: "sparkles", tint: .accentAmber, tintBackground: .accentAmberSoft,
                           title: "Discover new recipes", subtitle: "On-device AI finds recipes for your preferences")
            }
            .tint(.brandPrimary)
            .accessibilityIdentifier("preferences.discoverRecipes")
            if form.discoverRecipes, case .unavailable(let reason) = availability {
                Label(reason, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .card()
    }

    private var exclusionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "nosign", tint: .textSecondary, tintBackground: .bgMuted, title: "Exclusions", subtitle: "Comma-separated")
            InputField(icon: "hand.thumbsdown", placeholder: "Disliked ingredients", text: $form.dislikes, multiline: true)
            InputField(icon: "allergens", placeholder: "Allergies (e.g. peanuts, gluten)", text: $form.allergies, multiline: true)
        }
        .card()
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(icon: "wallet.bifold.fill", tint: .brandPrimary, tintBackground: .brandPrimarySoft, title: "Budget & region")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(form.weeklyBudget.eurosRounded)
                    .font(.screenTitle)
                    .tracking(-0.6)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText(value: form.weeklyBudget))
                    .animation(.snappy, value: form.weeklyBudget)
                Text("/ week")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 4) {
                Slider(value: $form.weeklyBudget, in: 20...150, step: 5) {
                    Text("Weekly budget")
                }
                .tint(.brandPrimary)
                HStack {
                    Text("€20")
                    Spacer()
                    Text("€150")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                InputField(icon: "mappin.and.ellipse", placeholder: "Postcode (e.g. 1012 AB)", text: $form.postcode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.postalCode)
                locationStatus
                    .animation(.snappy(duration: 0.2), value: location)
            }
            .task(id: form.postcode) { await resolvePostcode() }
        }
        .card()
    }

    @ViewBuilder
    private var locationStatus: some View {
        if isLookingUpPostcode {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding your area…")
            }
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
        } else if let postcodeError {
            Label(postcodeError, systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentCoral)
        } else if let location {
            HStack(spacing: 10) {
                IconCircle(systemName: "mappin", tint: .brandPrimary, background: .brandPrimarySoft, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(location.city ?? "Postcode \(location.postcode)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(location.postcode) · Offers matched for this area")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 8)
                Badge(text: location.regionId, foreground: .brandPrimaryDeep, background: .brandPrimarySoft)
            }
            .accessibilityElement(children: .combine)
            nearbyStoresList(location)
        } else if !form.legacyRegion.isEmpty {
            Text("Current region: \(form.legacyRegion). Add your postcode to update it.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        } else {
            Text("We use your postcode to find supermarket offers near you.")
                .font(.footnote)
                .foregroundStyle(Color.textTertiary)
        }
    }

    /// The supermarkets within 2 km that offers will come from.
    @ViewBuilder
    private func nearbyStoresList(_ location: PostcodeLocation) -> some View {
        let nearest = NearbyStores.nearestPerChain(location.nearbyStores)
        if location.latitude != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(nearest.isEmpty
                     ? "No supermarkets found within \(NearbyStores.distanceText(NearbyStores.radiusMeters)); offers come from all stores."
                     : "Supermarkets within \(NearbyStores.distanceText(NearbyStores.radiusMeters))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                FlowLayout {
                    ForEach(nearest) { store in
                        HStack(spacing: 6) {
                            StoreBadge(store: store.chain, size: 18)
                            Text(store.chain)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text(store.distanceText)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(Color.bgCanvas, in: Capsule())
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.top, 4)
            .accessibilityIdentifier("preferences.nearbyStores")
        }
    }

    private var routineLink: some View {
        NavigationLink {
            MealRoutineView()
                .onDisappear(perform: loadRoutineSummary)
        } label: {
            HStack(spacing: 12) {
                IconTile(systemName: "clock.fill", tint: .accentAmber, background: .accentAmberSoft)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Meal routine")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(routineSummary ?? "Not set yet")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preferences.routineLink")
    }

    // MARK: - Persistence

    private func savePreferences() {
        // A postcode whose lookup is still running is saved with its region now; the city follows when the
        // lookup finishes (see resolvePostcode).
        savedWhileLookingUp = isLookingUpPostcode
        if form.makePreferences(location: location).save() {
            didSave = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didSave = false
            }
        }
    }

    private func loadPreferences() {
        guard let saved = UserPreferences.loadFromUserDefaults() else { return }
        form = PreferencesForm(preferences: saved)
    }

    /// Resolves the typed postcode after a short pause. Runs whenever `postcode` changes; a newer
    /// keystroke cancels the previous lookup.
    private func resolvePostcode() async {
        isLookingUpPostcode = false
        let trimmed = form.postcode.trimmingCharacters(in: .whitespaces)
        guard let normalized = PostcodeLocationService.normalize(trimmed) else {
            location = nil
            postcodeError = PreferencesForm.postcodeError(for: trimmed)
            return
        }
        if location?.postcode == normalized { return }

        postcodeError = nil
        isLookingUpPostcode = true
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        do {
            let resolved = try await PostcodeLocationService.resolve(trimmed)
            guard !Task.isCancelled else { return }
            location = resolved
            if savedWhileLookingUp {  // fill in the city on what was already saved
                form.makePreferences(location: resolved).save()
                savedWhileLookingUp = false
            }
        } catch {
            postcodeError = error.localizedDescription
        }
        isLookingUpPostcode = false
    }

    private func loadRoutineSummary() {
        routineSummary = MealRoutine.load()?.summary
    }
}

// MARK: - Shared form pieces

struct SelectionIndicator: View {
    let isSelected: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.brandPrimary : Color.bgSurface)
            Circle()
                .strokeBorder(isSelected ? Color.clear : Color.borderSubtle, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct InputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 18)
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.callout)
        .foregroundStyle(Color.textPrimary)
        .padding(14)
        .background(Color.bgCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.borderSubtle))
    }
}

#Preview {
    PreferencesView()
}
