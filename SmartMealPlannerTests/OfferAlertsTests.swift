//
//  OfferAlertsTests.swift
//  SmartMealPlannerTests
//
//  Weekly local notifications on each store's offer day.
//

import Foundation
import Testing
import UserNotifications
@testable import SmartMealPlanner

/// Keeps scheduled requests in memory.
final class FakeNotificationCenter: NotificationScheduling {
    var requests: [UNNotificationRequest] = []
    var grantsPermission = true

    func add(_ request: UNNotificationRequest) async throws {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { grantsPermission }
}

@MainActor
@Suite("Offer alerts")
struct OfferAlertsTests {

    private let storage = IsolatedDefaults()

    private func store(_ id: String, _ name: String, day: String, offers: Bool = true) -> StoreSchedule {
        StoreSchedule(id: id, name: name, updateDay: day, fetchesOffers: offers, lastUpdatedAt: nil, nextUpdateAt: nil,
                      pricesChangedAt: nil, pricesAreCurrent: true, lastError: nil)
    }

    private var stores: [StoreSchedule] {
        [store("jumbo", "Jumbo", day: "Wednesday"), store("lidl", "Lidl", day: "Monday"),
         store("ah", "Albert Heijn", day: "Monday", offers: false)]
    }

    @Test(arguments: [("Sunday", 1), ("Monday", 2), ("wednesday", 4), ("Saturday", 7)])
    func weekdayNamesMapToCalendarWeekdays(name: String, weekday: Int) {
        #expect(OfferAlert.weekday(named: name) == weekday)
    }

    @Test func alertsAreOnlyForChosenStoresThatHaveOffers() {
        let alerts = OfferAlert.alerts(for: stores, enabled: ["jumbo", "ah"])
        #expect(alerts.map(\.storeName) == ["Jumbo"], "AH has only shelf prices, Lidl wasn't chosen")
        #expect(alerts.first?.weekday == 4)
        #expect(alerts.first?.title == "New offer week at Jumbo")
    }

    @Test func enablingSchedulesAWeeklyAlertOnEachStoresDay() async throws {
        let center = FakeNotificationCenter()
        let scheduler = OfferAlertScheduler(center: center, defaults: storage.defaults)
        scheduler.isEnabled = true

        await scheduler.reschedule(stores: stores, nearbyChains: nil)

        #expect(Set(center.requests.map(\.identifier)) == ["offer-alert.jumbo", "offer-alert.lidl"])
        let jumbo = try #require(center.requests.first { $0.identifier == "offer-alert.jumbo" })
        let trigger = try #require(jumbo.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats)
        #expect(trigger.dateComponents.weekday == 4 && trigger.dateComponents.hour == OfferAlert.hour)
        #expect(jumbo.content.title == "New offer week at Jumbo")
    }

    @Test func turningAlertsOffRemovesThemButLeavesOtherNotifications() async {
        let center = FakeNotificationCenter()
        center.requests = [UNNotificationRequest(identifier: "something-else", content: UNNotificationContent(), trigger: nil)]
        let scheduler = OfferAlertScheduler(center: center, defaults: storage.defaults)
        scheduler.isEnabled = true
        await scheduler.reschedule(stores: stores, nearbyChains: nil)

        scheduler.isEnabled = false
        await scheduler.reschedule(stores: stores, nearbyChains: nil)

        #expect(center.requests.map(\.identifier) == ["something-else"])
    }

    @Test func storesNearYouAreChosenByDefaultUntilYouChoose() {
        let scheduler = OfferAlertScheduler(center: FakeNotificationCenter(), defaults: storage.defaults)

        #expect(scheduler.storeIDs(for: stores, nearbyChains: ["Lidl"]) == ["lidl"])
        #expect(scheduler.storeIDs(for: stores, nearbyChains: nil) == ["jumbo", "lidl"], "unknown location: every store with offers")
        #expect(scheduler.storeIDs(for: stores, nearbyChains: ["Albert Heijn"]) == ["jumbo", "lidl"],
                "no nearby store has offers: every store with offers")

        scheduler.chosenStoreIDs = ["jumbo"]
        #expect(scheduler.storeIDs(for: stores, nearbyChains: ["Lidl"]) == ["jumbo"], "your choice wins")
    }

    @Test func permissionResultIsReported() async {
        let center = FakeNotificationCenter()
        center.grantsPermission = false
        #expect(await OfferAlertScheduler(center: center, defaults: storage.defaults).requestPermission() == false)
    }
}
