//
//  ShoppingListTests.swift
//  SmartMealPlannerTests
//
//  The List screen: adding offers and own items, editing, ticking off, the plan's groceries, filters and totals.
//

import Foundation
import Testing
@testable import SmartMealPlanner

@MainActor
@Suite("Grocery list")
struct ShoppingListTests {

    private let broccoli = Fixtures.offer(store: "Lidl", product: "Broccoli", price: 0.89)
    private let vla = Fixtures.offer(store: "Jumbo", product: "Campina vla", category: "Dairy", price: 0.80)

    private func planWith(_ lines: [GroceryLineItem]) -> AISuggestedWeekPlan {
        var plan = Fixtures.plan()
        plan.groceryLines = lines
        return plan
    }

    // MARK: - Offers

    @Test func addingAnOfferPutsItOnTheListWithItsStoreAndPrice() {
        var list = ShoppingList()
        list.add(broccoli)

        let item = try! #require(list.items.first)
        #expect((item.name, item.storeName, item.price, item.quantity) == ("Broccoli", "Lidl", 0.89, 1))
        #expect(item.source == .offer && item.isAdded)
        #expect(list.quantity(of: broccoli) == 1)
        #expect(list.quantity(of: vla) == 0)
    }

    @Test func addingTheSameOfferAgainRaisesTheQuantity() {
        var list = ShoppingList()
        list.add(broccoli)
        list.add(broccoli)

        #expect(list.items.count == 1)
        #expect(list.quantity(of: broccoli) == 2)
        #expect(abs(list.total() - 1.78) < 0.0001)
    }

    @Test func addingAnOfferAlreadyBoughtStartsANewLine() {
        var list = ShoppingList()
        list.add(broccoli)
        list.toggleChecked(list.items[0].id)
        list.add(broccoli)

        #expect(list.items.count == 2, "the bought one stays ticked off")
        #expect(list.items.map(\.isChecked) == [true, false])
        #expect(list.quantity(of: broccoli) == 1, "counts what's still to buy")
    }

    @Test func quantitiesForAllOffersMatchTheOneByOneLookup() {
        var list = ShoppingList()
        list.add(broccoli)
        list.add(broccoli)
        list.add(vla)
        list.toggleChecked(list.items[1].id)  // vla bought

        #expect(list.quantitiesByOffer == [broccoli.id: 2])
        #expect(list.quantitiesByOffer[broccoli.id] == list.quantity(of: broccoli))
        #expect(list.quantitiesByOffer[vla.id] == nil && list.quantity(of: vla) == 0)
    }

    // MARK: - Editing

    @Test func ownItemsNeedANameAndAnyStoreMeansNoStore() {
        var list = ShoppingList()
        list.addManual(name: "  ", storeName: nil, price: 1)
        list.addManual(name: " Bread ", storeName: ShoppingList.anyStore, price: 2.49, quantity: 2)

        #expect(list.items.map(\.name) == ["Bread"])
        #expect(list.items[0].storeName == nil)
        #expect(list.items[0].source == .manual)
        #expect(list.total() == 4.98)
    }

    @Test func editingChangesTheItemAndQuantityZeroRemovesIt() {
        var list = ShoppingList()
        list.add(broccoli)
        var item = list.items[0]
        item.name = "Broccoli (2 heads)"
        item.storeName = "Albert Heijn"
        item.price = 1.29
        item.quantity = 3
        list.update(item)

        #expect(list.items[0].name == "Broccoli (2 heads)")
        #expect(list.items[0].storeLabel == "Albert Heijn")
        #expect(abs(list.total() - 3.87) < 0.0001)

        item.quantity = 0
        list.update(item)
        #expect(list.items.isEmpty)
    }

    @Test func clearingTheNameKeepsTheOldOne() {
        var list = ShoppingList()
        list.addManual(name: "Milk", storeName: nil, price: nil)
        var item = list.items[0]
        item.name = ""
        list.update(item)
        #expect(list.items[0].name == "Milk")
    }

    @Test func tickedItemsCountAsBoughtAndCanBeRemoved() {
        var list = ShoppingList()
        list.add(broccoli)
        list.add(vla)
        list.toggleChecked(list.items[0].id)

        #expect(abs(list.total() - 1.69) < 0.0001)
        #expect(abs(list.remaining() - 0.80) < 0.0001)
        #expect(list.itemsLeft == 1, "the tab badge counts what's left to buy")

        list.removeChecked()
        #expect(list.items.map(\.name) == ["Campina vla"])
    }

    // MARK: - Plan

    @Test func planGroceriesArePutOnTheListOnce() {
        let plan = planWith([Fixtures.groceryLine("Rice", price: 1.20), Fixtures.groceryLine("Tomato", price: 4.20)])
        var list = ShoppingList()
        list.add(broccoli)

        list.syncPlan(plan)
        #expect(list.items.map(\.name) == ["Rice", "Tomato", "Broccoli"], "plan items first")
        #expect(list.items[0].source == .plan && !list.items[0].isAdded)
        #expect(list.items[0].amountText == "100 g")

        var rice = list.items[0]
        rice.quantity = 2
        list.update(rice)
        list.syncPlan(plan)
        #expect(list.items[0].quantity == 2, "syncing the same plan again keeps edits")
    }

    @Test func aNewPlanReplacesPlanItemsButKeepsAddedOnes() {
        var list = ShoppingList()
        list.syncPlan(planWith([Fixtures.groceryLine("Rice")]))
        list.add(broccoli)

        list.syncPlan(planWith([Fixtures.groceryLine("Pasta")]))
        #expect(list.items.map(\.name) == ["Pasta", "Broccoli"])

        list.syncPlan(nil)
        #expect(list.items.map(\.name) == ["Broccoli"], "clearing the plan removes its groceries")
    }

    @Test func planItemsWithAMatchedOfferBelongToThatStore() {
        var line = Fixtures.groceryLine("Tomato", price: 1.19)
        line.matchedOffer = Fixtures.offer(store: "Dirk", product: "Cherry tomaten", price: 1.19)
        var list = ShoppingList()
        list.syncPlan(planWith([line, Fixtures.groceryLine("Rice")]))

        #expect(list.items.map(\.storeLabel) == ["Dirk", ShoppingList.anyStore])
    }

    // MARK: - Filters and totals

    private func mixedList() -> ShoppingList {
        var list = ShoppingList()
        list.syncPlan(planWith([Fixtures.groceryLine("Rice", price: 1.20)]))
        list.add(broccoli)
        list.add(broccoli)
        list.add(vla)
        list.addManual(name: "Bread", storeName: "Jumbo", price: 2.00)
        return list
    }

    @Test func filtersAreAllThenAddedThenEachStoreWithAnyStoreLast() {
        let list = mixedList()
        #expect(list.filters == [.all, .added, .store("Jumbo"), .store("Lidl"), .store(ShoppingList.anyStore)])
        #expect(ShoppingList().filters == [.all])
    }

    @Test func addedFilterShowsOffersAndOwnItemsOnly() {
        let list = mixedList()
        #expect(Set(list.items(for: .added).map(\.name)) == ["Broccoli", "Campina vla", "Bread"])
        #expect(abs(list.total(for: .added) - 4.58) < 0.0001)
    }

    @Test func storeFilterAndStoreTotals() {
        let list = mixedList()
        #expect(Set(list.items(for: .store("Jumbo")).map(\.name)) == ["Campina vla", "Bread"])
        #expect(abs(list.total(for: .store("Jumbo")) - 2.80) < 0.0001)
        #expect(abs(list.total(for: .store("Lidl")) - 1.78) < 0.0001)

        let groups = list.groups(for: .all)
        #expect(groups.map(\.store) == ["Jumbo", "Lidl", ShoppingList.anyStore])
        #expect(abs(groups.map(\.total).reduce(0, +) - list.total()) < 0.0001, "store totals add up to the total")
        #expect(list.itemCount == 5, "counts quantities")
    }

    @Test func tickedItemsGoToTheBottomOfTheirStore() {
        var list = mixedList()
        let vlaID = list.items.first { $0.name == "Campina vla" }!.id
        list.toggleChecked(vlaID)
        #expect(list.groups(for: .store("Jumbo"))[0].items.map(\.name) == ["Bread", "Campina vla"])
    }

    // MARK: - Saving

    @Test func theListIsSavedAndRestored() {
        let storage = IsolatedDefaults()
        let store = ShoppingListStore(defaults: storage.defaults)
        store.change { $0.add(broccoli) }
        store.change { $0.addManual(name: "Bread", storeName: nil, price: 2) }

        let reopened = ShoppingListStore(defaults: storage.defaults)
        #expect(reopened.list == store.list)
        #expect(reopened.list.items.map(\.name) == ["Broccoli", "Bread"])
    }

    // MARK: - Spending

    /// Thursday 8 October 2026 (see Fixtures.now); its week runs Monday 5 to Sunday 11 October.
    private func day(_ offset: Int) -> Date { Fixtures.date(daysFromNow: offset) }

    @Test func tickingOffRecordsWhatWasSpentAndSaved() {
        var list = ShoppingList()
        let deal = Fixtures.offer(store: "Lidl", product: "Broccoli", price: 0.89, regularPrice: 1.29)
        list.add(deal)
        list.add(deal)
        list.toggleChecked(list.items[0].id, at: day(0))

        let purchase = try! #require(list.purchases.first)
        #expect(abs(purchase.amount - 1.78) < 0.0001)
        #expect(abs(purchase.offerSaving - 0.80) < 0.0001, "(1.29 - 0.89) × 2")

        list.toggleChecked(list.items[0].id, at: day(0))
        #expect(list.purchases.isEmpty, "un-ticking removes the record")
    }

    @Test func weeklySpendingComparesWithTheBudget() {
        var list = ShoppingList()
        list.addManual(name: "Groceries", storeName: "Jumbo", price: 40)
        list.addManual(name: "Fruit", storeName: "Lidl", price: 15)
        list.addManual(name: "Last week", storeName: "Lidl", price: 70)
        list.toggleChecked(list.items[0].id, at: day(0))   // this week
        list.toggleChecked(list.items[1].id, at: day(-3))  // Monday, still this week
        list.toggleChecked(list.items[2].id, at: day(-4))  // Sunday before: last week

        let weeks = list.weeklySpending(budget: 50, weeks: 3, now: day(0), calendar: Fixtures.calendar)
        #expect(weeks.count == 3)
        #expect(weeks[0].spent == 55 && weeks[0].isOverBudget && weeks[0].savedAgainstBudget == -5)
        #expect(weeks[1].spent == 70 && weeks[1].purchaseCount == 1)
        #expect(weeks[2].spent == 0 && weeks[2].savedAgainstBudget == 50)
        #expect(weeks[0].weekStart > weeks[1].weekStart, "this week first")
    }

    @Test func clearingTickedItemsKeepsTheSpendingHistory() {
        var list = ShoppingList()
        list.addManual(name: "Bread", storeName: nil, price: 2)
        list.toggleChecked(list.items[0].id, at: day(0))
        list.removeChecked()

        #expect(list.items.isEmpty)
        #expect(list.weeklySpending(budget: 50, now: day(0), calendar: Fixtures.calendar)[0].spent == 2)
    }

    @Test func correctingABoughtItemsPriceUpdatesWhatWasSpent() {
        var list = ShoppingList()
        list.addManual(name: "Cheese", storeName: nil, price: 3)
        list.toggleChecked(list.items[0].id, at: day(-1))
        var cheese = list.items[0]
        cheese.price = 4.5
        list.update(cheese)

        #expect(list.purchases.first?.amount == 4.5)
        #expect(list.purchases.first?.date == day(-1), "keeps when it was bought")
    }

    @Test func listsSavedBeforePurchasesExistStillLoad() throws {
        let old = #"{"items":[{"id":"0B6F2B42-1A8C-4E5E-9C38-6E2D4B2F1A11","name":"Milk","quantity":1,"source":"manual","isChecked":false}]}"#
        let list = try JSONDecoder().decode(ShoppingList.self, from: Data(old.utf8))
        #expect(list.items.map(\.name) == ["Milk"])
        #expect(list.purchases.isEmpty)
    }
}
