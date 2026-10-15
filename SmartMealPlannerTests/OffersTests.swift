//
//  OffersTests.swift
//  SmartMealPlannerTests
//
//  Filtering, grouping and display rules for the Offers screen.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Offers screen")
struct OffersTests {

    private let pasta = Fixtures.offer(store: "Albert Heijn", product: "Pasta", category: "Pantry", price: 0.99, regularPrice: 1.49, validUntil: Fixtures.date(daysFromNow: 1))
    private let broccoli = Fixtures.offer(store: "Lidl", product: "Broccoli", category: "Produce", price: 1.49, regularPrice: 1.99, validUntil: Fixtures.date(daysFromNow: 2))
    private let rice = Fixtures.offer(store: "Jumbo", product: "Rice", category: "Pantry", price: 2.29, regularPrice: 2.99, validUntil: Fixtures.date(daysFromNow: 6))
    private let chicken = Fixtures.offer(store: "Albert Heijn", product: "Chicken", category: "Meat", price: 4.99, regularPrice: nil, validUntil: Fixtures.date(daysFromNow: 5))
    private let expired = Fixtures.offer(store: "Plus", product: "Tomatoes", category: "Produce", price: 1.19, regularPrice: 1.79, validUntil: Fixtures.date(daysFromNow: -1))

    private var all: [SupermarketOffer] { [rice, chicken, expired, broccoli, pasta] }

    private func names(_ offers: [SupermarketOffer]) -> [String] { offers.map(\.productName) }

    // MARK: - Filter chips

    @Test func categoriesAreUniqueAndAlphabetical() {
        #expect(OffersList(offers: all).categories == ["Meat", "Pantry", "Produce"])
    }

    @Test func allShowsEveryOfferSoonestToExpireFirst() {
        let list = OffersList(offers: all, selectedCategory: nil)

        #expect(names(list.filtered) == ["Tomatoes", "Pasta", "Broccoli", "Chicken", "Rice"])
    }

    @Test func selectingACategoryShowsOnlyThatCategory() {
        let list = OffersList(offers: all, selectedCategory: "Pantry")

        #expect(names(list.filtered) == ["Pasta", "Rice"])
    }

    @Test func emptyCategoryShowsNothing() {
        #expect(OffersList(offers: all, selectedCategory: "Dairy").filtered.isEmpty)
    }

    // MARK: - Grouping

    @Test func endingSoonIsStillValidOffersExpiringWithinThreeDays() {
        let list = OffersList(offers: all)

        let soon = list.endingSoon(now: Fixtures.now, calendar: Fixtures.calendar)
        let others = list.otherOffers(now: Fixtures.now, calendar: Fixtures.calendar)

        #expect(names(soon) == ["Pasta", "Broccoli"])
        #expect(names(others) == ["Tomatoes", "Chicken", "Rice"], "Everything not ending soon, including expired offers")
    }

    @Test func livePriceDropsAreNeverEndingSoon() {
        var drop = Fixtures.offer(product: "Broccoli", price: 0.99, regularPrice: 1.49, validUntil: Fixtures.date(daysFromNow: 1))
        drop.observedAt = Fixtures.date(daysFromNow: -6)
        let list = OffersList(offers: [drop, pasta])

        #expect(names(list.endingSoon(now: Fixtures.now, calendar: Fixtures.calendar)) == ["Pasta"])
        #expect(names(list.otherOffers(now: Fixtures.now, calendar: Fixtures.calendar)) == ["Broccoli"])
    }

    @Test func offersEndingTogetherShowTheBiggestSavingFirst() {
        let day = Fixtures.date(daysFromNow: 7)
        let small = Fixtures.offer(product: "Small", price: 1.00, regularPrice: 1.20, validUntil: day)
        let big = Fixtures.offer(product: "Big", price: 1.00, regularPrice: 2.50, validUntil: day)

        #expect(names(OffersList(offers: [small, big]).filtered) == ["Big", "Small"])
    }

    @Test func recipeIngredientsComeFirstAmongOffersEndingTogether() {
        let day = Fixtures.date(daysFromNow: 7)
        let snack = Fixtures.offer(product: "Chocolate", price: 1.00, regularPrice: 3.00, validUntil: day)
        var broccoli = Fixtures.offer(product: "Broccoli", price: 0.99, regularPrice: 1.49, validUntil: day)
        broccoli.ingredientName = "Broccoli"

        #expect(names(OffersList(offers: [snack, broccoli]).filtered) == ["Broccoli", "Chocolate"])
    }

    // MARK: - Store updates

    private func store(_ id: String, day: String, next: Date?, offers: Bool = true, current: Bool? = true,
                       error: String? = nil) -> StoreSchedule {
        StoreSchedule(id: id, name: id.capitalized, updateDay: day, fetchesOffers: offers,
                      lastUpdatedAt: Fixtures.date(daysFromNow: -1), nextUpdateAt: next,
                      pricesChangedAt: nil, pricesAreCurrent: current, lastError: error)
    }

    @Test func nextUpdateNamesTheStoresRefreshedSoonest() {
        let stores = [
            store("jumbo", day: "Wednesday", next: Fixtures.date(daysFromNow: 6)),
            store("dirk", day: "Wednesday", next: Fixtures.date(daysFromNow: 6)),
            store("poiesz", day: "Sunday", next: Fixtures.date(daysFromNow: 3)),
        ]
        #expect(OffersList.nextUpdateText(stores: stores, now: Fixtures.now) == "Next update: Poiesz on Sunday")
        #expect(OffersList.nextUpdateText(stores: Array(stores.prefix(2)), now: Fixtures.now)
                == "Next update: Dirk and Jumbo on Wednesday")
        #expect(OffersList.nextUpdateText(stores: [], now: Fixtures.now) == nil)
    }

    @Test func storeStatusShowsTheWeeklyDayAndProblemsLast() {
        let statuses = OffersList.storeStatuses([
            store("plus", day: "Monday", next: nil, offers: false, current: false),
            store("lidl", day: "Monday", next: nil, error: "HTTP 503"),
            store("jumbo", day: "Wednesday", next: nil),
            store("spar", day: "Monday", next: nil, offers: false, current: true),
        ], now: Fixtures.now)

        #expect(statuses.map(\.name) == ["Jumbo", "Spar", "Lidl", "Plus"])
        #expect(statuses[0].schedule == "Every Wednesday")
        #expect(statuses[0].detail.hasPrefix("Offers · updated"))
        #expect(statuses[1].detail.hasPrefix("Shelf prices only"))
        #expect(statuses[2].isWarning && statuses[2].detail.contains("failed"))
        #expect(statuses[3].isWarning && statuses[3].detail.contains("out of date"))
    }

    @Test func groupingRespectsTheSelectedCategory() {
        let list = OffersList(offers: all, selectedCategory: "Produce")

        #expect(names(list.endingSoon(now: Fixtures.now, calendar: Fixtures.calendar)) == ["Broccoli"])
        #expect(names(list.otherOffers(now: Fixtures.now, calendar: Fixtures.calendar)) == ["Tomatoes"])
    }

    // MARK: - Savings banner

    @Test func totalSavingsAddsUpEveryDiscountRegardlessOfCategory() {
        let list = OffersList(offers: all, selectedCategory: "Meat")

        // Pasta 0.50 + broccoli 0.50 + rice 0.70 + tomatoes 0.60; chicken has no regular price.
        #expect(abs(list.totalSavings - 2.30) < 0.0001)
        #expect(OffersList(offers: []).totalSavings == 0)
    }

    // MARK: - Offer card

    @Test func discountPercentIsRoundedPercentageOffTheRegularPrice() {
        #expect(Fixtures.offer(product: "Chicken", price: 4.99, regularPrice: 6.49).discountPercent == 23)
        #expect(pasta.discountPercent == 34)
    }

    @Test(arguments: [nil, 0.0, 4.99, 3.00] as [Double?])
    func noDiscountBadgeWithoutARealDiscount(regularPrice: Double?) {
        #expect(Fixtures.offer(product: "Chicken", price: 4.99, regularPrice: regularPrice).discountPercent == nil)
    }

    @Test(arguments: [
        ("Albert Heijn", "AH"),
        ("Jumbo", "J"),
        ("lidl", "L"),
        ("Albert Heijn To Go", "AH"),
    ])
    func storeAvatarShowsUpToTwoInitials(store: String, initials: String) {
        #expect(Fixtures.offer(store: store, product: "Item", price: 1).storeInitials == initials)
    }
}
