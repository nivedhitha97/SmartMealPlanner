//
//  MyOffers.swift
//  SmartMealPlanner
//
//  Deals the user adds from a supermarket's folder. Albert Heijn blocks apps from reading its Bonus offers, so
//  the free and legal way to plan with them is to look at AH's own Bonus page and add the deals worth having.
//  They are saved on the phone and used like any other offer until they end.
//

import Combine
import Foundation

enum AlbertHeijn {
    static let name = "Albert Heijn"
    /// AH's Bonus page; the AH app opens it when installed (it claims ah.nl links), else Safari.
    static let bonusURL = URL(string: "https://www.ah.nl/bonus")!

    /// The end of the Bonus week (Monday to Sunday) that `now` is in: Sunday 23:59:59, Amsterdam time.
    static func bonusWeekEnd(after now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return calendar.date(byAdding: DateComponents(day: 7, second: -1), to: monday)!
    }
}

/// A deal as the user types it in.
struct OfferDraft: Equatable {
    static let categories = ["Produce", "Meat", "Fish", "Dairy", "Bakery", "Pantry", "Snacks", "Drinks", "Groceries"]

    var productName = ""
    var storeName = AlbertHeijn.name
    var category = "Groceries"
    var offerPrice: Double?
    var regularPrice: Double?
    var dealText = ""
    var unitLabel = "item"
    var validUntil = AlbertHeijn.bonusWeekEnd()
    /// The recipe ingredient this is, so the planner can use it (e.g. "Chicken Breast").
    var ingredientName: String?

    var isValid: Bool {
        !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (offerPrice ?? 0) > 0
    }

    func offer(id: UUID = UUID()) -> SupermarketOffer? {
        guard isValid, let offerPrice else { return nil }
        let deal = dealText.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unitLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        var offer = SupermarketOffer(
            id: id,
            storeName: storeName,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            offerPrice: offerPrice,
            regularPrice: regularPrice.flatMap { $0 > offerPrice ? $0 : nil },
            unitLabel: unit.isEmpty ? "item" : unit,
            validUntil: validUntil,
            regionId: SupermarketOffer.nationalRegionId,
            notes: deal.isEmpty ? nil : deal
        )
        offer.dealText = deal.isEmpty ? nil : deal
        offer.ingredientName = ingredientName
        offer.source = SupermarketOffer.addedByYou
        return offer
    }
}

@MainActor
final class MyOffersStore: ObservableObject {
    static let defaultsKey = "myOffers_v1"

    @Published private(set) var offers: [SupermarketOffer]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        // Ended deals are dropped when the app starts, so the list never grows without limit.
        offers = Self.saved(in: defaults).filter { $0.validUntil >= now }
    }

    /// Deals saved on this phone, including ended ones (the planner filters by date).
    nonisolated static func saved(in defaults: UserDefaults = .standard) -> [SupermarketOffer] {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode([SupermarketOffer].self, from: $0) } ?? []
    }

    func add(_ offer: SupermarketOffer) {
        offers.append(offer)
        save()
    }

    func remove(id: UUID) {
        offers.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(offers) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// The feed's offers plus the user's deals that haven't ended.
    nonisolated static func merged(_ feed: [SupermarketOffer], with mine: [SupermarketOffer],
                                   now: Date = .now) -> [SupermarketOffer] {
        feed + mine.filter { $0.validUntil >= now }
    }
}
