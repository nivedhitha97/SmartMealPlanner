//
//  WeeklyOffersView.swift
//  SmartMealPlanner
//

import SwiftUI

struct WeeklyOffersView: View {

    @State private var offers: [SupermarketOffer] = []
    @State private var loadError: String?
    @State private var selectedCategory: String?
    @State private var region = ""

    private var list: OffersList {
        OffersList(offers: offers, selectedCategory: selectedCategory)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    ContentUnavailableView(
                        "Could not load offers",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            let endingSoon = list.endingSoon()
                            if list.totalSavings > 0 { savingsBanner }
                            categoryFilters
                            if list.filtered.isEmpty {
                                Text("No offers in this category right now.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 24)
                            }
                            offerGroup("Ending soon", endingSoon)
                            offerGroup(endingSoon.isEmpty ? "All deals" : "More deals", list.otherOffers())
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadOffers() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Deals near you")
                .font(.screenTitle)
                .tracking(-0.6)
                .foregroundStyle(Color.textPrimary)
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
                Text(region.isEmpty ? "All regions" : region)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
                Text("· \(offers.count) offers this week")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var savingsBanner: some View {
        HStack(spacing: 14) {
            IconCircle(systemName: "flame.fill", tint: .accentAmber, background: .bgSurface, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Save up to \(list.totalSavings.euros)")
                    .font(.callout.bold())
                    .foregroundStyle(Color.textPrimary)
                Text("Matched offers are used automatically in your grocery list.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.accentAmberSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(list.categories, id: \.self) { category in
                    Chip(title: category, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -24)
    }

    @ViewBuilder
    private func offerGroup(_ title: String, _ items: [SupermarketOffer]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.textSecondary)
                ForEach(items) { offer in
                    OfferCard(offer: offer)
                }
            }
        }
    }

    private func loadOffers() async {
        loadError = nil
        region = UserPreferences.loadFromUserDefaults()?.shoppingRegion ?? ""
        do {
            offers = try JSONLoader.load("offers", as: [SupermarketOffer].self)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Offer card

private struct OfferCard: View {
    let offer: SupermarketOffer

    private var avatarColors: (Color, Color) {
        let palette: [(Color, Color)] = [
            (.brandPrimarySoft, .brandPrimaryDeep),
            (.accentCoralSoft, .accentCoral),
            (.accentAmberSoft, .accentAmber),
            (.bgMuted, .textSecondary)
        ]
        let sum = offer.storeName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(offer.storeInitials)
                .font(.callout.bold())
                .foregroundStyle(avatarColors.1)
                .frame(width: 52, height: 52)
                .background(avatarColors.0, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(offer.productName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(offer.storeName) · \(offer.category)")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                Label("Until \(offer.validUntil.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let discountPercent = offer.discountPercent {
                    Text("−\(discountPercent)%")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentCoral)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(Color.accentCoralSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(offer.offerPrice.euros)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.brandPrimaryDeep)
                if let regular = offer.regularPrice {
                    Text(regular.euros)
                        .font(.caption)
                        .strikethrough()
                        .foregroundStyle(Color.textTertiary)
                }
                Text("per \(offer.unitLabel)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .card(padding: 14, radius: 20)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WeeklyOffersView()
}
