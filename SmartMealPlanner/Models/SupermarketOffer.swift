//
//  SupermarketOffer.swift
//  SmartMealPlanner
//

import Foundation

/// A promotional line item from a weekly flyer or the live grocery feed, scoped to a region or store.
struct SupermarketOffer: Identifiable, Codable, Hashable {
    let id: UUID
    let storeName: String
    let productName: String
    let category: String
    /// Price per unit (e.g. per pack or kg — informational for planning).
    let offerPrice: Double
    let regularPrice: Double?
    let unitLabel: String
    let validUntil: Date
    /// "NL" for national prices that apply in every region.
    let regionId: String
    let notes: String?
    /// When the live feed saw this price. Set for live price drops, whose end date isn't known.
    var observedAt: Date? = nil
    /// The recipe ingredient this product is, when the feed recognised it (e.g. "Chicken Breast").
    var ingredientName: String? = nil
    /// The store's deal, e.g. "1+1 gratis" or "2 voor €5,00"; `offerPrice` is then the price per item.
    var dealText: String? = nil
    /// Product photo (about 300 px wide) hosted by the store; nil when the store has none.
    var imageURL: URL? = nil

    /// Region id of offers that apply across the Netherlands.
    static let nationalRegionId = "NL"

    /// Whether this is a live price drop rather than a flyer offer with a known end date.
    var isLivePriceDrop: Bool { observedAt != nil }

    var savings: Double? {
        guard let regularPrice else { return nil }
        return max(0, regularPrice - offerPrice)
    }
}
