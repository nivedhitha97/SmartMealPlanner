//
//  PreferencesForm.swift
//  SmartMealPlanner
//
//  Editable state of the Preferences screen and the rules for turning it into saved
//  `UserPreferences`. Kept free of SwiftUI so it can be unit tested.
//

import Foundation

struct PreferencesForm: Equatable {

    static let dietOptions = ["Vegetarian", "Non-Vegetarian", "Vegan", "High Protein"]
    static let cuisineOptions = ["Indian", "Italian", "Dutch", "Asian", "Mexican", "Greek", "French"]

    var dietType = "Vegetarian"
    var selectedCuisines: Set<String> = []
    /// Comma-separated, as typed.
    var dislikes = ""
    /// Comma-separated, as typed.
    var allergies = ""
    var weeklyBudget: Double = 50
    var postcode = ""
    /// Region text from preferences saved before postcode lookup existed. Empty once a postcode is set,
    /// because the region is then re-derived from the postcode.
    var legacyRegion = ""
    var breakfastRecipePreference: BreakfastRecipePreference = .includeRecipes
    var people = 1

    init() {}

    init(preferences: UserPreferences) {
        dietType = preferences.dietType
        selectedCuisines = Set(preferences.cuisines)
        dislikes = preferences.dislikes.joined(separator: ", ")
        allergies = preferences.allergies.joined(separator: ", ")
        weeklyBudget = preferences.budgetWeekly
        postcode = preferences.postcode
        legacyRegion = preferences.postcode.isEmpty ? preferences.shoppingRegion : ""
        breakfastRecipePreference = preferences.breakfastRecipePreference
        people = preferences.people
    }

    mutating func toggleCuisine(_ cuisine: String) {
        if selectedCuisines.contains(cuisine) {
            selectedCuisines.remove(cuisine)
        } else {
            selectedCuisines.insert(cuisine)
        }
    }

    /// Builds the preferences to save.
    /// - Parameter location: the result of looking up `postcode`, or nil if the lookup hasn't finished (or there is
    ///   no postcode). A valid postcode is saved either way: its region comes from the postcode itself, only the
    ///   city needs the lookup.
    func makePreferences(location: PostcodeLocation?) -> UserPreferences {
        let hasPostcode = !postcode.trimmingCharacters(in: .whitespaces).isEmpty
        let location = location ?? Self.offlineLocation(for: postcode)
        return UserPreferences(
            dietType: dietType,
            cuisines: selectedCuisines.sorted(),
            dislikes: Self.splitList(dislikes),
            allergies: Self.splitList(allergies),
            budgetWeekly: weeklyBudget,
            shoppingRegion: location?.shoppingRegion ?? (hasPostcode ? "" : legacyRegion),
            postcode: location?.postcode ?? "",
            breakfastRecipePreference: breakfastRecipePreference,
            people: people,
            nearbyStores: location?.nearbyStores ?? []
        )
    }

    /// The location of a valid postcode without the online city lookup.
    static func offlineLocation(for raw: String) -> PostcodeLocation? {
        guard let postcode = PostcodeLocationService.normalize(raw.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return PostcodeLocation(postcode: postcode, city: nil, regionId: PostcodeLocationService.regionId(forPostcode: postcode))
    }

    /// Message to show under the postcode field, or nil while the field is empty, still being typed, or valid.
    static func postcodeError(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, PostcodeLocationService.normalize(trimmed) == nil else { return nil }
        // Only complain once a full-length postcode has been typed.
        let typed = trimmed.filter { !$0.isWhitespace }.count
        return typed >= 6 ? PostcodeLookupError.invalidFormat.errorDescription : nil
    }

    /// "olives,  mushrooms , " → ["olives", "mushrooms"]
    static func splitList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
