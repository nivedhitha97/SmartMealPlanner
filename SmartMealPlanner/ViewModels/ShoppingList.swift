//
//  ShoppingList.swift
//  SmartMealPlanner
//
//  The editable grocery list: items from the weekly plan, offers added on the Offers screen, and items typed
//  in by hand. Kept free of SwiftUI so it can be unit tested; `ShoppingListStore` saves it.
//

import Combine
import Foundation

struct ShoppingListItem: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        /// From the weekly plan's grocery list; replaced when a new plan is generated.
        case plan
        /// Added from the Offers screen.
        case offer
        /// Typed in on the List screen.
        case manual
    }

    var id = UUID()
    var name: String
    /// nil when it can be bought anywhere.
    var storeName: String?
    /// Price per item; nil when unknown.
    var price: Double?
    /// The usual price per item when `price` is an offer price, for counting offer savings.
    var regularPrice: Double?
    var quantity = 1
    /// Pack size or amount, e.g. "500 g" or "1050 g".
    var amountText: String?
    var source: Source
    /// The offer this was added from, so adding it again raises the quantity.
    var offerID: UUID?
    var dealText: String?
    var imageURL: URL?
    var isChecked = false

    var lineTotal: Double { (price ?? 0) * Double(quantity) }

    /// Added by the user (from an offer or by hand) rather than generated from the plan.
    var isAdded: Bool { source != .plan }

    /// Store name for grouping and filters.
    var storeLabel: String { storeName ?? ShoppingList.anyStore }
}

/// What the List screen shows.
enum ShoppingListFilter: Hashable {
    case all
    /// Items added from offers or by hand.
    case added
    case store(String)

    var title: String {
        switch self {
        case .all: "All"
        case .added: "Added"
        case .store(let name): name
        }
    }
}

/// An item ticked off as bought: what was paid and saved, and when.
struct Purchase: Codable, Hashable, Identifiable {
    /// The shopping list item's id.
    var id: UUID
    var name: String
    var storeName: String?
    var amount: Double
    /// Saved compared with the regular price (offers only).
    var offerSaving: Double
    var date: Date
}

/// Spending in one week (Monday to Sunday) against the weekly budget.
struct WeekSpending: Identifiable, Equatable {
    var id: Date { weekStart }
    let weekStart: Date
    let spent: Double
    let offerSavings: Double
    let budget: Double
    let purchaseCount: Int

    /// Budget left over (negative when over budget).
    var savedAgainstBudget: Double { budget - spent }
    var isOverBudget: Bool { spent > budget }
    var progress: Double { budget > 0 ? min(spent / budget, 1) : 0 }
}

struct StoreGroup: Identifiable, Equatable {
    var id: String { store }
    let store: String
    let items: [ShoppingListItem]
    var total: Double { items.map(\.lineTotal).reduce(0, +) }
}

struct ShoppingList: Codable, Equatable {
    static let anyStore = "Any store"

    private(set) var items: [ShoppingListItem] = []
    /// The plan the `.plan` items came from.
    private(set) var planID: UUID?
    /// Everything ticked off as bought, newest last; kept for `purchaseHistoryWeeks`.
    private(set) var purchases: [Purchase] = []

    static let purchaseHistoryWeeks = 26

    init() {}

    enum CodingKeys: String, CodingKey {
        case items, planID, purchases
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([ShoppingListItem].self, forKey: .items) ?? []
        planID = try c.decodeIfPresent(UUID.self, forKey: .planID)
        // Lists saved before purchases were recorded have no history.
        purchases = try c.decodeIfPresent([Purchase].self, forKey: .purchases) ?? []
    }

    // MARK: - Offers

    /// Adds an offer, or one more of it if it's already on the list (and not yet bought).
    mutating func add(_ offer: SupermarketOffer) {
        if let index = items.firstIndex(where: { $0.offerID == offer.id && !$0.isChecked }) {
            items[index].quantity += 1
            return
        }
        items.append(ShoppingListItem(
            name: offer.productName,
            storeName: offer.storeName,
            price: offer.offerPrice,
            regularPrice: offer.regularPrice,
            amountText: offer.unitLabel == "item" ? nil : offer.unitLabel,
            source: .offer,
            offerID: offer.id,
            dealText: offer.dealText,
            imageURL: offer.imageURL
        ))
    }

    /// How many of this offer are on the list and not yet bought (0 if none).
    func quantity(of offer: SupermarketOffer) -> Int {
        items.first { $0.offerID == offer.id && !$0.isChecked }?.quantity ?? 0
    }

    /// `quantity(of:)` for every offer on the list at once, so a screen of offers doesn't search the list per card.
    var quantitiesByOffer: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for item in items where !item.isChecked {
            if let id = item.offerID, result[id] == nil { result[id] = item.quantity }
        }
        return result
    }

    // MARK: - Editing

    /// Adds an item typed in by hand. Blank names are ignored.
    mutating func addManual(name: String, storeName: String?, price: Double?, quantity: Int = 1) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(ShoppingListItem(name: trimmed, storeName: Self.normalisedStore(storeName), price: price,
                                      quantity: max(1, quantity), source: .manual))
    }

    /// Replaces an item with an edited copy. A quantity below 1 removes it.
    mutating func update(_ item: ShoppingListItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard item.quantity >= 1 else {
            items.remove(at: index)
            return
        }
        var edited = item
        edited.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if edited.name.isEmpty { edited.name = items[index].name }
        edited.storeName = Self.normalisedStore(item.storeName)
        items[index] = edited
        if edited.isChecked, let purchase = purchases.firstIndex(where: { $0.id == edited.id }) {
            let date = purchases[purchase].date  // a corrected price or quantity updates what was spent
            purchases[purchase] = Self.purchase(of: edited, at: date)
        }
    }

    mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    /// Ticks an item off as bought (recording the purchase) or un-ticks it (removing the record).
    mutating func toggleChecked(_ id: UUID, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isChecked.toggle()
        purchases.removeAll { $0.id == id }
        if items[index].isChecked {
            purchases.append(Self.purchase(of: items[index], at: date))
            let cutoff = date.addingTimeInterval(-Double(Self.purchaseHistoryWeeks) * 7 * 86_400)
            purchases.removeAll { $0.date < cutoff }
        }
    }

    private static func purchase(of item: ShoppingListItem, at date: Date) -> Purchase {
        let saving = max(0, (item.regularPrice ?? 0) - (item.price ?? 0)) * Double(item.quantity)
        return Purchase(id: item.id, name: item.name, storeName: item.storeName, amount: item.lineTotal,
                        offerSaving: item.regularPrice == nil ? 0 : saving, date: date)
    }

    // MARK: - Spending

    /// Spending per week (Monday to Sunday) for the last `weeks` weeks, this week first.
    func weeklySpending(budget: Double, weeks: Int = 4, now: Date = Date(), calendar: Calendar = .current) -> [WeekSpending] {
        var calendar = calendar
        calendar.firstWeekday = 2  // weeks start on Monday
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inWeek = purchases.filter { $0.date >= start && $0.date < end }
            return WeekSpending(weekStart: start, spent: inWeek.map(\.amount).reduce(0, +),
                                offerSavings: inWeek.map(\.offerSaving).reduce(0, +), budget: budget,
                                purchaseCount: inWeek.count)
        }
    }

    mutating func removeChecked() {
        items.removeAll(where: \.isChecked)
    }

    // MARK: - Plan

    /// Puts the plan's grocery lines on the list, replacing those of an earlier plan. Added items are kept.
    /// Does nothing if the list already has this plan, so edits to plan items survive relaunches.
    mutating func syncPlan(_ plan: AISuggestedWeekPlan?) {
        guard plan?.id != planID else { return }
        items.removeAll { $0.source == .plan }
        planID = plan?.id
        guard let plan else { return }
        items.insert(contentsOf: plan.groceryLines.map { line in
            ShoppingListItem(
                name: line.ingredientName,
                storeName: line.matchedOffer?.storeName,
                price: line.estimatedLinePrice,
                amountText: "\(Int(line.totalGrams.rounded())) g",
                source: .plan,
                offerID: nil,
                dealText: line.matchedOffer?.dealText,
                imageURL: line.matchedOffer?.imageURL
            )
        }, at: 0)
    }

    // MARK: - Filters and totals

    /// Stores on the list, alphabetically, with "Any store" last.
    var stores: [String] {
        let names = Set(items.map(\.storeLabel))
        return names.subtracting([Self.anyStore]).sorted() + (names.contains(Self.anyStore) ? [Self.anyStore] : [])
    }

    /// Filter chips: All, Added (if anything was added), then each store.
    var filters: [ShoppingListFilter] {
        [.all] + (items.contains(where: \.isAdded) ? [.added] : []) + stores.map { .store($0) }
    }

    func items(for filter: ShoppingListFilter) -> [ShoppingListItem] {
        switch filter {
        case .all: items
        case .added: items.filter(\.isAdded)
        case .store(let name): items.filter { $0.storeLabel == name }
        }
    }

    /// The filtered items grouped by store (in `stores` order), unticked items first within each store.
    func groups(for filter: ShoppingListFilter) -> [StoreGroup] {
        let filtered = items(for: filter)
        return stores.compactMap { store in
            let inStore = filtered.filter { $0.storeLabel == store }
            guard !inStore.isEmpty else { return nil }
            return StoreGroup(store: store, items: inStore.filter { !$0.isChecked } + inStore.filter(\.isChecked))
        }
    }

    func total(for filter: ShoppingListFilter = .all) -> Double {
        items(for: filter).map(\.lineTotal).reduce(0, +)
    }

    /// Total of the items not yet ticked off.
    func remaining(for filter: ShoppingListFilter = .all) -> Double {
        items(for: filter).filter { !$0.isChecked }.map(\.lineTotal).reduce(0, +)
    }

    var itemCount: Int { items.map(\.quantity).reduce(0, +) }

    /// Items still to buy (counting quantities), for the List tab's badge.
    var itemsLeft: Int { items.filter { !$0.isChecked }.map(\.quantity).reduce(0, +) }

    // MARK: - Sharing

    /// The list as plain text for sharing (WhatsApp, Messages, Notes, email): what's still to buy in `filter`, by
    /// store, with amounts, quantities, prices and deals. Nil when nothing is left to buy.
    func shareText(for filter: ShoppingListFilter = .all) -> String? {
        let groups = groups(for: filter).compactMap { group -> (String, [ShoppingListItem])? in
            let toBuy = group.items.filter { !$0.isChecked }
            return toBuy.isEmpty ? nil : (group.store, toBuy)
        }
        guard !groups.isEmpty else { return nil }
        let toBuy = groups.flatMap(\.1)
        let count = toBuy.map(\.quantity).reduce(0, +)
        var lines = ["🛒 Grocery list" + (filter == .all ? "" : " · \(filter.title)"),
                     "\(count) \(count == 1 ? "item" : "items")" + (toBuy.contains { $0.price != nil }
                        ? " · about \(toBuy.map(\.lineTotal).reduce(0, +).euros)" : "")]
        for (store, items) in groups {
            lines.append("")
            lines.append(store)
            for item in items {
                var line = "• " + item.name
                // Real amounts ("500 g"), not "pack" or "item".
                if let amount = item.amountText, amount.contains(where: \.isNumber), !item.name.contains(amount) {
                    line += " (\(amount))"
                }
                if item.quantity > 1 { line += " ×\(item.quantity)" }
                if item.price != nil { line += " – \(item.lineTotal.euros)" }
                if let deal = item.dealText, !deal.isEmpty { line += " [\(deal)]" }
                lines.append(line)
            }
        }
        lines.append("")
        lines.append("Made with Smart Meal Planner")
        return lines.joined(separator: "\n")
    }

    private static func normalisedStore(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty || trimmed == anyStore ? nil : trimmed
    }
}

/// The shopping list shared by the Plan, Offers and List screens, saved in UserDefaults.
@MainActor
final class ShoppingListStore: ObservableObject {
    static let defaultsKey = "shoppingList_v1"

    @Published private(set) var list: ShoppingList
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(ShoppingList.self, from: $0) } ?? ShoppingList()
    }

    /// Changes the list and saves it.
    func change(_ edit: (inout ShoppingList) -> Void) {
        var copy = list
        edit(&copy)
        guard copy != list else { return }
        list = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
