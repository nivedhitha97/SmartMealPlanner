//
//  WeeklyOffersView.swift
//  SmartMealPlanner
//

import SwiftUI

struct WeeklyOffersView: View {

    var service: GroceryDataService = GroceryDataServices.shared

    @EnvironmentObject private var shopping: ShoppingListStore
    @EnvironmentObject private var myOffers: MyOffersStore

    @State private var offers: [SupermarketOffer] = []
    @State private var grocery: GroceryData?
    @State private var selectedCategory: String?
    @State private var selectedStore: String?
    @State private var region = ""
    /// Chains within 2 km of the saved postcode; nil when unknown.
    @State private var nearbyChains: Set<String>?
    @State private var nearMeOnly = true
    @State private var addingDeal = false

    private var list: OffersList {
        let all = MyOffersStore.merged(offers, with: myOffers.offers)
        return OffersList(offers: nearMeOnly ? OffersList.nearby(all, chains: nearbyChains) : all,
                          selectedCategory: selectedCategory, selectedStore: selectedStore)
    }

    /// AH's Bonus card shows unless the stores near the postcode are known and AH isn't one of them.
    private var showsAlbertHeijn: Bool {
        guard let nearbyChains, nearMeOnly else { return true }
        return nearbyChains.contains { $0.caseInsensitiveCompare(AlbertHeijn.name) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Group {
                if grocery == nil {
                    ProgressView("Fetching today's prices…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header
                            let endingSoon = list.endingSoon()
                            if list.totalSavings > 0 { savingsBanner }
                            if showsAlbertHeijn { albertHeijnCard }
                            VStack(alignment: .leading, spacing: 10) {
                                storeFilters
                                categoryFilters
                            }
                            if list.filtered.isEmpty {
                                Text("No offers in this category right now.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 24)
                            }
                            offerGroup("Ending soon", endingSoon)
                            offerGroup(endingSoon.isEmpty ? "All deals" : "More deals", list.otherOffers())
                            if let stores = grocery?.stores, !stores.isEmpty {
                                storeUpdates(OffersList.storeStatuses(stores))
                            }
                            if list.offers.contains(where: { $0.source == SupermarketOffer.openPrices }) {
                                Text("Prices marked Open Prices were reported by shoppers. © Open Food Facts contributors, ODbL.")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("offers.openPricesCredit")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await loadOffers(forceRefresh: true) }
                }
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadOffers() }
            .sheet(isPresented: $addingDeal) {
                AddOfferView { myOffers.add($0) }
            }
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
                Text(nearMeOnly && nearbyChains != nil
                     ? "Within \(NearbyStores.distanceText(NearbyStores.radiusMeters))"
                     : region.isEmpty ? "All regions" : region)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandPrimary)
                Text("· \(list.offers.count) offers this week")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            if let grocery {
                Label(
                    OffersList.freshnessText(source: grocery.source, updatedAt: grocery.updatedAt),
                    systemImage: grocery.source == .live ? "dot.radiowaves.left.and.right" : "wifi.slash"
                )
                .font(.footnote)
                .foregroundStyle(grocery.source == .live ? Color.brandPrimaryDeep : Color.textTertiary)
                .accessibilityIdentifier("offers.freshness")
                if let next = OffersList.nextUpdateText(stores: grocery.stores) {
                    Label(next, systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(Color.textTertiary)
                        .accessibilityIdentifier("offers.nextUpdate")
                }
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

    /// Albert Heijn doesn't let apps read its Bonus offers: open AH's own Bonus page, then add the deals worth having.
    private var albertHeijnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StoreBadge(store: AlbertHeijn.name, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Albert Heijn Bonus")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("AH doesn't share its offers with apps. Check this week's Bonus and add the deals you want.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button {
                    ExternalLinks.open(AlbertHeijn.bonusURL)
                } label: {
                    Label("Open Bonus", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("offers.ah.openBonus")
                Button {
                    addingDeal = true
                } label: {
                    Label("Add a deal", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("offers.addDeal")
            }
            .font(.subheadline.weight(.semibold))
            .tint(Color.brandPrimary)
        }
        .card(padding: 16, radius: 20)
    }

    /// One chip per supermarket; "All stores" clears it.
    private var storeFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if nearbyChains != nil {
                    Chip(title: "Near me", isSelected: nearMeOnly) {
                        nearMeOnly.toggle()
                        if let store = selectedStore, !list.stores.contains(store) { selectedStore = nil }
                    }
                    .accessibilityIdentifier("offers.nearMe")
                }
                Chip(title: "All stores", isSelected: selectedStore == nil) {
                    selectedStore = nil
                }
                ForEach(list.stores, id: \.self) { store in
                    StoreChip(store: store, isSelected: selectedStore == store) {
                        selectedStore = store
                        if let category = selectedCategory, !list.categories.contains(category) {
                            selectedCategory = nil  // that category has no offers at this store
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -24)
        .accessibilityIdentifier("offers.storeFilter")
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
                    OfferCard(offer: offer, quantityInList: shopping.list.quantity(of: offer)) {
                        shopping.change { $0.add(offer) }
                    }
                    .contextMenu {
                        if offer.isAddedByYou {
                            Button("Delete deal", systemImage: "trash", role: .destructive) {
                                myOffers.remove(id: offer.id)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Each supermarket's weekly refresh day and whether its data is current.
    private func storeUpdates(_ statuses: [StoreStatus]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STORE UPDATES")
                .font(.footnote.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
            VStack(spacing: 0) {
                ForEach(statuses) { status in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: status.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(status.isWarning ? Color.accentAmber : Color.brandPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(status.detail)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(status.schedule)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if status.id != statuses.last?.id {
                        Divider()
                    }
                }
            }
            .card(padding: 14, radius: 20)
        }
        .accessibilityIdentifier("offers.storeUpdates")
    }

    private func loadOffers(forceRefresh: Bool = false) async {
        let preferences = UserPreferences.loadFromUserDefaults()
        region = preferences?.shoppingRegion ?? ""
        nearbyChains = preferences?.nearbyChains
        let latest = await service.latest(forceRefresh: forceRefresh)
        offers = latest.offers
        grocery = latest
    }
}

// MARK: - Offer card

private struct OfferCard: View {
    let offer: SupermarketOffer
    /// How many are on the shopping list (0 if none).
    let quantityInList: Int
    let onAdd: () -> Void

    /// The product photo, or a placeholder while it loads, if it fails or if there is none.
    @ViewBuilder
    private var thumbnail: some View {
        if let imageURL = offer.imageURL {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                        .frame(width: 52, height: 52)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                } else {
                    photoPlaceholder
                }
            }
        } else {
            photoPlaceholder
        }
    }

    /// A neutral placeholder while the photo loads or when there is none.
    private var photoPlaceholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 20))
            .foregroundStyle(Color.textTertiary)
            .frame(width: 52, height: 52)
            .background(Color.bgMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }

    /// "+" on the photo; once added it shows how many are on the list, and tapping adds one more.
    private var addButton: some View {
        Button(action: onAdd) {
            Group {
                if quantityInList > 0 {
                    Text("\(quantityInList)")
                        .font(.caption.bold())
                        .monospacedDigit()
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(quantityInList > 0 ? Color.brandPrimaryDeep : Color.brandPrimary, in: Circle())
            .overlay(Circle().strokeBorder(Color.bgSurface, lineWidth: 2))
            .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.increase, trigger: quantityInList)
        .accessibilityLabel(quantityInList > 0
                            ? "\(quantityInList) on your list. Add one more \(offer.productName)"
                            : "Add \(offer.productName) to your list")
        .accessibilityIdentifier("offer.add.\(offer.productName)")
    }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
                .overlay(alignment: .bottomTrailing) {
                    addButton
                        .offset(x: 8, y: 8)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(offer.productName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(offer.storeName) · \(offer.category)")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                if offer.isAddedByYou {
                    Label("Added by you", systemImage: "person.crop.circle.badge.plus")
                        .font(.caption)
                        .foregroundStyle(Color.brandPrimaryDeep)
                } else if offer.source == SupermarketOffer.openPrices {
                    Label("Reported on Open Prices", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                if let observedAt = offer.observedAt {
                    Label("Price drop · seen \(observedAt.formatted(.relative(presentation: .named)))",
                          systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Label("Until \(offer.validUntil.formatted(.dateTime.month(.abbreviated).day()))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                if let dealText = offer.dealText {
                    Text(dealText)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentCoral)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 7)
                        .background(Color.accentCoralSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let discountPercent = offer.discountPercent {
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
                    .lineLimit(1)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .accessibilityElement(children: .combine)
        }
        .card(padding: 14, radius: 20)
    }
}

#Preview {
    WeeklyOffersView()
        .environmentObject(ShoppingListStore())
        .environmentObject(MyOffersStore())
}
