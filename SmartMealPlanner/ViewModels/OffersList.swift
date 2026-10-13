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

    /// Categories for the filter chips, alphabetical and without duplicates.
    var categories: [String] {
        Array(Set(offers.map(\.category))).sorted()
    }

    /// Offers in the selected category, soonest to expire first.
    var filtered: [SupermarketOffer] {
        offers
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .sorted { $0.validUntil < $1.validUntil }
    }

    /// Filtered offers that are still valid and expire within `endingSoonDays`.
    func endingSoon(now: Date = Date(), calendar: Calendar = .current) -> [SupermarketOffer] {
        let cutoff = calendar.date(byAdding: .day, value: Self.endingSoonDays, to: now) ?? now
        return filtered.filter { $0.validUntil >= now && $0.validUntil <= cutoff }
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
