//
//  OffersList.swift
//  SmartMealPlanner
//
//  Filtering and grouping rules for the Offers screen, kept free of SwiftUI so they can be unit tested.
//

import Foundation

struct OffersList {

    /// How close to expiry an offer has to be to appear under "Ending soon".
    static let endingSoonDays = 3

    var offers: [SupermarketOffer]
    /// nil means "All".
    var selectedCategory: String?
    /// nil means every store.
    var selectedStore: String? = nil

    /// Categories for the filter chips, alphabetical and without duplicates (within the selected store).
    var categories: [String] {
        Array(Set(offers.filter { selectedStore == nil || $0.storeName == selectedStore }.map(\.category))).sorted()
    }

    /// Stores for the store filter, alphabetical.
    var stores: [String] {
        Array(Set(offers.map(\.storeName))).sorted()
    }

    /// Offers in the selected store and category, soonest to expire first. Offers ending together show
    /// recipe ingredients first, then the biggest saving.
    var filtered: [SupermarketOffer] {
        offers
            .filter { selectedStore == nil || $0.storeName == selectedStore }
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .sorted { a, b in
                if a.validUntil != b.validUntil { return a.validUntil < b.validUntil }
                if (a.ingredientName != nil) != (b.ingredientName != nil) { return a.ingredientName != nil }
                return (a.savings ?? 0) > (b.savings ?? 0)
            }
    }

    /// Filtered flyer offers that are still valid and expire within `endingSoonDays`.
    /// Live price drops have no known end date, so they never count as ending soon.
    func endingSoon(now: Date = Date(), calendar: Calendar = .current) -> [SupermarketOffer] {
        let cutoff = calendar.date(byAdding: .day, value: Self.endingSoonDays, to: now) ?? now
        return filtered.filter { !$0.isLivePriceDrop && $0.validUntil >= now && $0.validUntil <= cutoff }
    }

    /// Filtered offers that aren't ending soon.
    func otherOffers(now: Date = Date(), calendar: Calendar = .current) -> [SupermarketOffer] {
        let soonIDs = Set(endingSoon(now: now, calendar: calendar).map(\.id))
        return filtered.filter { !soonIDs.contains($0.id) }
    }

    /// Combined savings across every offer, regardless of the selected category.
    var totalSavings: Double {
        offers.compactMap(\.savings).reduce(0, +)
    }

    /// Which stores refresh next: "Next update: Poiesz on Sunday". Nil when nothing is scheduled.
    static func nextUpdateText(stores: [StoreSchedule], now: Date = Date()) -> String? {
        let upcoming = stores.compactMap { store in store.nextUpdateAt.map { (store, $0) } }
        guard let soonest = upcoming.map(\.1).min() else { return nil }
        let next = upcoming.filter { abs($0.1.timeIntervalSince(soonest)) < 60 * 60 }.map(\.0)
        let names = ListFormatter.localizedString(byJoining: next.map(\.name).sorted())
        let when = soonest <= now ? "today" : "on \(next[0].updateDay)"
        return "Next update: \(names) \(when)"
    }

    /// One line per store for the "Store updates" section, stores with problems last.
    static func storeStatuses(_ stores: [StoreSchedule], now: Date = Date()) -> [StoreStatus] {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return stores.map { store in
            let updated = store.lastUpdatedAt.map { "updated \(formatter.localizedString(for: $0, relativeTo: now))" }
            var detail = [store.fetchesOffers ? "Offers" : "Shelf prices only", updated].compactMap { $0 }
                .joined(separator: " · ")
            var warning = false
            if store.lastError != nil {
                detail = "Last update failed; trying again"
                warning = true
            } else if store.pricesAreCurrent == false && !store.fetchesOffers {
                detail = "Prices out of date: the source stopped updating this store"
                warning = true
            }
            return StoreStatus(id: store.id, name: store.name, schedule: "Every \(store.updateDay)",
                               detail: detail, isWarning: warning)
        }
        .sorted { ($0.isWarning ? 1 : 0, $0.name) < ($1.isWarning ? 1 : 0, $1.name) }
    }

    /// Short line under the title saying whether these are live prices and how fresh they are.
    static func freshnessText(source: GroceryDataSource, updatedAt: Date?, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let age = updatedAt.map { formatter.localizedString(for: $0, relativeTo: now) }
        switch source {
        case .live:
            return age.map { "Live prices · updated \($0)" } ?? "Live prices"
        case .cached:
            return age.map { "Offline · prices from \($0)" } ?? "Offline · saved prices"
        case .bundled:
            return "Offline · sample offers"
        }
    }
}

struct StoreStatus: Identifiable, Equatable {
    let id: String
    let name: String
    /// "Every Wednesday"
    let schedule: String
    let detail: String
    let isWarning: Bool
}

extension SupermarketOffer {

    /// Rounded percentage off the regular price, or nil when there's no real discount.
    var discountPercent: Int? {
        guard let regularPrice, regularPrice > 0, regularPrice > offerPrice else { return nil }
        return Int(((regularPrice - offerPrice) / regularPrice * 100).rounded())
    }

    /// Up to two initials for the store avatar: "Albert Heijn" → "AH", "Jumbo" → "J".
    var storeInitials: String {
        let words = storeName.split(separator: " ")
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}
