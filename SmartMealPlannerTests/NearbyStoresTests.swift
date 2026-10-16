//
//  NearbyStoresTests.swift
//  SmartMealPlannerTests
//
//  Supermarkets within 2 km of the postcode, and offers limited to them.
//

import CoreLocation
import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Nearby stores")
struct NearbyStoresTests {

    /// Around 1062 JB, Amsterdam.
    private let home = CLLocationCoordinate2D(latitude: 52.3702, longitude: 4.8460)

    /// A point `meters` north of home (one degree of latitude is about 111 km).
    private func north(_ meters: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: home.latitude + meters / 111_000, longitude: home.longitude)
    }

    @Test(arguments: [
        ("Albert Heijn Bos en Lommerweg", "Albert Heijn"),
        ("AH to go Station Lelylaan", "Albert Heijn"),
        ("Jumbo Hoofdweg", "Jumbo"),
        ("PLUS Mercatorplein", "Plus"),
        ("Dirk van den Broek", "Dirk"),
        ("Lidl", "Lidl"),
    ])
    func placeNamesAreMatchedToChains(place: String, chain: String) {
        #expect(NearbyStores.chain(forPlaceName: place) == chain)
    }

    @Test(arguments: ["Sparkling Wines", "Toko Plusmarkt", "Bakkerij Jansen", "Ekoplaza"])
    func otherShopsAreNotMatched(place: String) {
        #expect(NearbyStores.chain(forPlaceName: place) == nil)
    }

    @Test func onlyStoresWithinTwoKilometresCountNearestFirst() {
        let stores = NearbyStores.stores(from: [
            ("Jumbo Hoofdweg", north(1_200)),
            ("Albert Heijn Bos en Lommerweg", north(350)),
            ("Lidl Far Away", north(3_500)),
            ("Bakkerij Jansen", north(100)),
        ], around: home)

        #expect(stores.map(\.chain) == ["Albert Heijn", "Jumbo"])
        #expect(abs(stores[0].distanceMeters - 350) < 15)
    }

    @Test func nearestBranchPerChain() {
        let stores = NearbyStores.stores(from: [
            ("Albert Heijn XL", north(1_800)),
            ("Albert Heijn Bos en Lommerweg", north(350)),
            ("Jumbo Hoofdweg", north(900)),
        ], around: home)

        let nearest = NearbyStores.nearestPerChain(stores)
        #expect(nearest.map(\.branchName) == ["Albert Heijn Bos en Lommerweg", "Jumbo Hoofdweg"])
    }

    @Test(arguments: [(340.0, "350 m"), (1_234.0, "1.2 km"), (2_000.0, "2 km")])
    func distancesReadNaturally(meters: Double, text: String) {
        #expect(NearbyStores.distanceText(meters) == text)
    }

    @Test func offersAreLimitedToNearbyChains() {
        let offers = [Fixtures.offer(store: "Lidl", product: "Broccoli", price: 0.89),
                      Fixtures.offer(store: "Jumbo", product: "Vla", price: 0.8),
                      Fixtures.offer(store: "Dirk", product: "Kip", price: 4.99)]

        #expect(OffersList.nearby(offers, chains: ["jumbo", "Lidl"]).map(\.productName) == ["Broccoli", "Vla"])
        #expect(OffersList.nearby(offers, chains: nil).count == 3, "unknown location: every store")
    }

    @Test func plannerUsesOnlyOffersFromNearbyStores() async throws {
        let tomato = Fixtures.ingredient("Tomato", price: 0.4)
        let salad = Fixtures.recipe("Salad", cuisine: "Greek", ingredients: [(tomato, 150)])
        let far = Fixtures.offer(store: "Dirk", product: "Cherry Tomato 250g", price: 0.99, region: "NL")
        let near = Fixtures.offer(store: "Jumbo", product: "Cherry Tomato 500g", price: 1.79, region: "NL")
        var preferences = Fixtures.preferences()
        preferences.nearbyStores = [NearbyStore(chain: "Jumbo", branchName: "Jumbo Hoofdweg", distanceMeters: 900,
                                                latitude: 52.37, longitude: 4.85)]

        let plan = try await LocalHeuristicAIPlanner().generateWeeklySuggestions(
            preferences: preferences, routine: MealRoutine(breakfastType: .outside, lunchType: .fixed, dinnerType: .outside),
            recipes: [salad], weeklyOffers: [far, near])

        #expect(plan.groceryLines.first?.matchedOffer?.storeName == "Jumbo", "Dirk is cheaper but not within 2 km")
    }

    @Test func preferencesSavedWithoutNearbyStoresMeanEveryStore() throws {
        let old = #"{"dietType":"Vegan","cuisines":[],"dislikes":[],"allergies":[],"budgetWeekly":60,"postcode":"1062 JB"}"#
        let preferences = try JSONDecoder().decode(UserPreferences.self, from: Data(old.utf8))
        #expect(preferences.nearbyStores.isEmpty)
        #expect(preferences.nearbyChains == nil)
    }

    @Test func nearbyStoresFromTheLookupAreSaved() {
        var form = PreferencesForm()
        form.postcode = "1062 JB"
        let store = NearbyStore(chain: "Albert Heijn", branchName: "AH", distanceMeters: 350, latitude: 52.37, longitude: 4.84)
        let location = PostcodeLocation(postcode: "1062 JB", city: "Amsterdam", regionId: "NL-North",
                                        latitude: 52.37, longitude: 4.846, nearbyStores: [store])

        #expect(form.makePreferences(location: location).nearbyChains == ["Albert Heijn"])
    }

    @Test func theSameBranchFoundTwiceCountsOnce() {
        let stores = NearbyStores.stores(from: [
            ("Albert Heijn Bos en Lommerweg", north(350)),
            ("Albert Heijn", north(360)),       // same shop from the name search, 10 m off
            ("Albert Heijn XL", north(1_500)),  // a different branch
        ], around: home)

        #expect(NearbyStores.deduplicated(stores).count == 2)
    }
}
