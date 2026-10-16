//
//  PreferencesFormTests.swift
//  SmartMealPlannerTests
//
//  Covers the logic behind the Preferences screen: loading saved preferences into the form,
//  building what gets saved, and postcode validation.
//

import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Preferences form")
struct PreferencesFormTests {

    private let amsterdam = PostcodeLocation(postcode: "1012 AB", city: "Amsterdam", regionId: "NL-North")

    // MARK: - Defaults & editing

    @Test func newFormHasSensibleDefaults() {
        let form = PreferencesForm()

        #expect(form.dietType == "Vegetarian")
        #expect(form.selectedCuisines.isEmpty)
        #expect(form.weeklyBudget == 50)
        #expect(form.postcode.isEmpty)
        #expect(form.legacyRegion.isEmpty)
        #expect(form.breakfastRecipePreference == .includeRecipes)
    }

    @Test func togglingACuisineSelectsThenDeselectsIt() {
        var form = PreferencesForm()

        form.toggleCuisine("Italian")
        #expect(form.selectedCuisines == ["Italian"])

        form.toggleCuisine("Greek")
        #expect(form.selectedCuisines == ["Italian", "Greek"])

        form.toggleCuisine("Italian")
        #expect(form.selectedCuisines == ["Greek"])
    }

    @Test(arguments: [
        ("olives,  mushrooms , ,peanut butter ", ["olives", "mushrooms", "peanut butter"]),
        ("", []),
        (" , ,", []),
        ("gluten", ["gluten"]),
    ])
    func commaSeparatedListsAreTrimmedAndEmptyItemsDropped(raw: String, expected: [String]) {
        #expect(PreferencesForm.splitList(raw) == expected)
    }

    // MARK: - Saving

    @Test func savedPreferencesReflectTheForm() {
        var form = PreferencesForm()
        form.dietType = "Vegan"
        form.selectedCuisines = ["Mexican", "Asian", "Indian"]
        form.dislikes = "olives, mushrooms"
        form.allergies = "peanuts"
        form.weeklyBudget = 85
        form.breakfastRecipePreference = .granolaMuesliOnly

        let saved = form.makePreferences(location: nil)

        #expect(saved.dietType == "Vegan")
        #expect(saved.cuisines == ["Asian", "Indian", "Mexican"], "Cuisines are saved in a stable, sorted order")
        #expect(saved.dislikes == ["olives", "mushrooms"])
        #expect(saved.allergies == ["peanuts"])
        #expect(saved.budgetWeekly == 85)
        #expect(saved.breakfastRecipePreference == .granolaMuesliOnly)
        #expect(saved.postcode.isEmpty)
        #expect(saved.shoppingRegion.isEmpty)
    }

    @Test func peopleCountRoundTripsThroughTheForm() {
        var form = PreferencesForm()
        #expect(form.people == 1, "one person by default")
        form.people = 4

        let saved = form.makePreferences(location: nil)
        #expect(saved.people == 4)
        #expect(PreferencesForm(preferences: saved).people == 4)
    }

    @Test func postcodeIsSavedEvenBeforeItsLookupFinishes() {
        var form = PreferencesForm()
        form.postcode = "1062jb"

        let saved = form.makePreferences(location: nil)

        #expect(saved.postcode == "1062 JB")
        #expect(saved.shoppingRegion == "NL-North", "region comes from the postcode; the city follows later")
    }

    @Test func invalidPostcodeIsNotSaved() {
        var form = PreferencesForm()
        form.postcode = "0123AB"

        let saved = form.makePreferences(location: nil)

        #expect(saved.postcode.isEmpty)
        #expect(saved.shoppingRegion.isEmpty)
    }

    @Test func resolvedPostcodeSetsRegionAndNormalizedPostcode() {
        var form = PreferencesForm()
        form.postcode = "1012ab"

        let saved = form.makePreferences(location: amsterdam)

        #expect(saved.postcode == "1012 AB")
        #expect(saved.shoppingRegion == "Amsterdam, NL-North")
    }

    @Test func regionFallsBackToPostcodeRegionWhenCityIsUnknown() {
        var form = PreferencesForm()
        form.postcode = "9711 CS"
        let offline = PostcodeLocation(postcode: "9711 CS", city: nil, regionId: "NL-North")

        #expect(form.makePreferences(location: offline).shoppingRegion == "NL-North")
    }

    @Test func typedPostcodeReplacesTheOldRegionEvenBeforeItsLookupFinishes() {
        var form = PreferencesForm(preferences: legacyPreferences(region: "Amsterdam"))
        form.postcode = "3511 AX"

        let saved = form.makePreferences(location: nil)

        #expect(saved.postcode == "3511 AX")
        #expect(saved.shoppingRegion == "NL-West", "the old region is replaced by the postcode's own region")
    }

    @Test func loadingFillsTheFormFromSavedPreferences() {
        let saved = UserPreferences(
            dietType: "High Protein",
            cuisines: ["Greek", "Italian"],
            dislikes: ["olives", "mushrooms"],
            allergies: ["peanuts", "gluten"],
            budgetWeekly: 120,
            shoppingRegion: "Amsterdam, NL-North",
            postcode: "1012 AB",
            breakfastRecipePreference: .granolaMuesliOnly
        )

        let form = PreferencesForm(preferences: saved)

        #expect(form.dietType == "High Protein")
        #expect(form.selectedCuisines == ["Greek", "Italian"])
        #expect(form.dislikes == "olives, mushrooms")
        #expect(form.allergies == "peanuts, gluten")
        #expect(form.weeklyBudget == 120)
        #expect(form.postcode == "1012 AB")
        #expect(form.legacyRegion.isEmpty, "With a postcode the region is re-derived, not shown as legacy text")
        #expect(form.breakfastRecipePreference == .granolaMuesliOnly)
    }

    @Test func savingWhatWasLoadedProducesTheSamePreferences() {
        let original = UserPreferences(
            dietType: "Vegetarian",
            cuisines: ["Greek", "Italian"],
            dislikes: ["olives"],
            allergies: [],
            budgetWeekly: 60,
            shoppingRegion: amsterdam.shoppingRegion,
            postcode: amsterdam.postcode
        )

        let roundTripped = PreferencesForm(preferences: original).makePreferences(location: amsterdam)

        #expect(roundTripped == original)
    }

    // MARK: - Preferences saved before postcode lookup existed

    @Test func legacyRegionIsShownAndKeptUntilAPostcodeIsEntered() {
        let form = PreferencesForm(preferences: legacyPreferences(region: "NL-North"))

        #expect(form.legacyRegion == "NL-North")
        #expect(form.makePreferences(location: nil).shoppingRegion == "NL-North")
    }

    @Test func clearingASavedPostcodeClearsTheRegion() {
        let saved = UserPreferences(
            dietType: "Vegetarian", cuisines: [], dislikes: [], allergies: [], budgetWeekly: 50,
            shoppingRegion: "Amsterdam, NL-North", postcode: "1012 AB"
        )
        var form = PreferencesForm(preferences: saved)
        form.postcode = ""

        let resaved = form.makePreferences(location: nil)

        #expect(resaved.postcode.isEmpty)
        #expect(resaved.shoppingRegion.isEmpty)
    }

    // MARK: - Postcode validation

    @Test(arguments: ["", "  ", "1", "101", "1012", "1012 A", "12345"])
    func noErrorWhileEmptyOrStillTyping(raw: String) {
        #expect(PreferencesForm.postcodeError(for: raw) == nil)
    }

    @Test(arguments: ["1012 AB", "1012ab", " 3511ax "])
    func noErrorForAValidPostcode(raw: String) {
        #expect(PreferencesForm.postcodeError(for: raw) == nil)
    }

    @Test(arguments: ["0123 AB", "ABCD12", "1012 A1", "123456"])
    func errorForAFullLengthInvalidPostcode(raw: String) {
        #expect(PreferencesForm.postcodeError(for: raw) == "Enter a Dutch postcode, e.g. 1012 AB.")
    }

    @Test(arguments: [
        ("1012ab", "1012 AB", "NL-North"),
        ("3511 AX", "3511 AX", "NL-West"),
        ("5611", "5611", "NL-South"),
        ("7511ja", "7511 JA", "NL-East"),
        ("9711 cs", "9711 CS", "NL-North"),
    ])
    func postcodesAreNormalizedAndMappedToARegion(raw: String, normalized: String, region: String) throws {
        let result = try #require(PostcodeLocationService.normalize(raw))
        #expect(result == normalized)
        #expect(PostcodeLocationService.regionId(forPostcode: result) == region)
    }

    // MARK: - Helpers

    private func legacyPreferences(region: String) -> UserPreferences {
        UserPreferences(
            dietType: "Vegetarian", cuisines: [], dislikes: [], allergies: [], budgetWeekly: 50,
            shoppingRegion: region, postcode: ""
        )
    }
}
