//
//  MyOffersTests.swift
//  SmartMealPlannerTests
//
//  Deals the user adds from Albert Heijn's Bonus (or any folder): what is saved, for how long, and how they join
//  the feed's offers.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Deals you add")
struct MyOffersTests {

    private func freshDefaults() -> UserDefaults {
        let name = "MyOffersTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func amsterdam(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        return formatter.date(from: text)!
    }

    private func draft(price: Double? = 1.99, regular: Double? = 2.79) -> OfferDraft {
        var draft = OfferDraft()
        draft.productName = "  AH Kipfilet "
        draft.offerPrice = price
        draft.regularPrice = regular
        draft.dealText = "25% korting"
        draft.unitLabel = "300 g"
        draft.ingredientName = "Chicken Breast"
        draft.validUntil = Fixtures.date(daysFromNow: 3)
        return draft
    }

    @Test func bonusWeekEndsOnSundayNightInAmsterdam() {
        let friday = amsterdam("2026-10-16T14:00:00+02:00")
        #expect(AlbertHeijn.bonusWeekEnd(after: friday) == amsterdam("2026-10-18T23:59:59+02:00"))
        let monday = amsterdam("2026-10-12T00:30:00+02:00")
        #expect(AlbertHeijn.bonusWeekEnd(after: monday) == amsterdam("2026-10-18T23:59:59+02:00"))
        let sunday = amsterdam("2026-10-25T20:00:00+01:00")  // winter time
        #expect(AlbertHeijn.bonusWeekEnd(after: sunday) == amsterdam("2026-10-25T23:59:59+01:00"))
    }

    @Test func newDealDefaultsToAlbertHeijnUntilSunday() {
        let draft = OfferDraft()
        #expect(draft.storeName == "Albert Heijn")
        #expect(draft.validUntil == AlbertHeijn.bonusWeekEnd())
        #expect(!draft.isValid, "needs a name and a price")
    }

    @Test func dealNeedsANameAndAPositivePrice() {
        #expect(draft().isValid)
        #expect(!draft(price: nil).isValid)
        #expect(!draft(price: 0).isValid)
        var unnamed = draft()
        unnamed.productName = "   "
        #expect(!unnamed.isValid)
        #expect(unnamed.offer() == nil)
    }

    @Test func dealBecomesAnOfferMarkedAsYours() throws {
        let offer = try #require(draft().offer())
        #expect(offer.productName == "AH Kipfilet")
        #expect(offer.storeName == "Albert Heijn")
        #expect((offer.offerPrice, offer.regularPrice) == (1.99, 2.79))
        #expect(offer.dealText == "25% korting" && offer.unitLabel == "300 g")
        #expect(offer.ingredientName == "Chicken Breast")
        #expect(offer.regionId == SupermarketOffer.nationalRegionId, "applies wherever there is an AH")
        #expect(offer.isAddedByYou)
    }

    @Test func normalPriceIsKeptOnlyWhenHigher() throws {
        #expect(try #require(draft(regular: 1.50).offer()).regularPrice == nil)
        #expect(try #require(draft(regular: nil).offer()).regularPrice == nil)
    }

    @Test func dealsAreSavedOnThePhone() throws {
        let defaults = freshDefaults()
        let store = MyOffersStore(defaults: defaults, now: Fixtures.now)
        let offer = try #require(draft().offer())
        store.add(offer)

        #expect(MyOffersStore(defaults: defaults, now: Fixtures.now).offers.map(\.id) == [offer.id], "still there after a restart")
        #expect(MyOffersStore.saved(in: defaults).map(\.productName) == ["AH Kipfilet"])

        store.remove(id: offer.id)
        #expect(MyOffersStore(defaults: defaults, now: Fixtures.now).offers.isEmpty)
    }

    @Test func endedDealsAreDroppedAtLaunch() throws {
        let defaults = freshDefaults()
        let store = MyOffersStore(defaults: defaults, now: Fixtures.now)
        var old = draft()
        old.validUntil = Fixtures.date(daysFromNow: -1)
        store.add(try #require(old.offer()))
        store.add(try #require(draft().offer()))

        #expect(MyOffersStore(defaults: defaults, now: Fixtures.now).offers.count == 1)
    }

    @Test func mergedOffersAddCurrentDealsToTheFeed() throws {
        let feed = [Fixtures.offer(store: "Lidl", product: "Broccoli", category: "Produce", price: 1.19,
                                   regularPrice: 1.59, validUntil: Fixtures.date(daysFromNow: 2))]
        var old = draft()
        old.validUntil = Fixtures.date(daysFromNow: -1)
        let mine = [try #require(draft().offer()), try #require(old.offer())]

        let merged = MyOffersStore.merged(feed, with: mine, now: Fixtures.now)
        #expect(merged.map(\.productName) == ["Broccoli", "AH Kipfilet"])
    }

    @Test func linkedDealIsThePlannersPriceForThatIngredient() throws {
        let deal = try #require(draft().offer())
        let other = Fixtures.offer(store: "Jumbo", product: "Kipfilet blokjes", category: "Meat", price: 3.49,
                                   regularPrice: nil, validUntil: Fixtures.date(daysFromNow: 2))
        let best = LocalHeuristicAIPlanner().bestOffer(forIngredientName: "Chicken Breast", in: [other, deal])
        #expect(best?.id == deal.id)
    }

    @Test func feedOffersSayWhoReportedThem() throws {
        let json = """
        [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "storeName": "Albert Heijn", "productName": "AH Kipfilet",
          "category": "Meat", "offerPrice": 1.99, "regularPrice": 2.79, "unitLabel": "300 g",
          "validUntil": "2026-10-18T21:59:59Z", "regionId": "NL", "notes": null, "source": "Open Prices"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let offer = try #require(try decoder.decode([SupermarketOffer].self, from: Data(json.utf8)).first)
        #expect(offer.source == SupermarketOffer.openPrices)
        #expect(!offer.isAddedByYou)
    }
}
