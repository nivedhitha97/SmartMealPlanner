//
//  OfferAlerts.swift
//  SmartMealPlanner
//
//  Local notifications when a supermarket's new offer week is in the app. Each store is updated on a known day of
//  the week (see the grocery database schedule), so the phone schedules one weekly alert per store, on that day
//  after the morning update. Free, no server or push certificate needed, and it keeps working without opening the app.
//

import Foundation
import UserNotifications

/// One weekly alert: which store, and when.
struct OfferAlert: Equatable {
    static let identifierPrefix = "offer-alert."
    /// Alerts go out at this hour (local time) on the store's update day; the feed is published by about 08:30.
    static let hour = 9

    let storeID: String
    let storeName: String
    /// Calendar weekday: 1 = Sunday … 7 = Saturday.
    let weekday: Int

    var identifier: String { Self.identifierPrefix + storeID }
    var title: String { "New offers at \(storeName)" }
    var body: String { "This week's \(storeName) offers are in Smart Meal Planner." }

    /// Weekly alerts for the chosen stores that fetch offers (shelf-price-only stores have no offer week).
    static func alerts(for stores: [StoreSchedule], enabled storeIDs: Set<String>) -> [OfferAlert] {
        stores.compactMap { store in
            guard store.fetchesOffers, storeIDs.contains(store.id), let weekday = weekday(named: store.updateDay) else {
                return nil
            }
            return OfferAlert(storeID: store.id, storeName: store.name, weekday: weekday)
        }
    }

    /// "Monday" → 2 (Calendar's weekday numbering, Sunday = 1).
    static func weekday(named name: String) -> Int? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        return names.firstIndex(of: name.lowercased()).map { $0 + 1 }
    }
}

/// What OfferAlertScheduler needs from UNUserNotificationCenter, so tests can check what's scheduled.
protocol NotificationScheduling: AnyObject {
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationScheduling {}

@MainActor
final class OfferAlertScheduler {
    static let shared = OfferAlertScheduler()

    static let enabledKey = "offerAlertsEnabled"
    static let storesKey = "offerAlertStores"

    private let center: NotificationScheduling
    private let defaults: UserDefaults

    init(center: NotificationScheduling = UNUserNotificationCenter.current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// Stores chosen for alerts; nil until the user changes the choice (then the stores near them are used).
    var chosenStoreIDs: Set<String>? {
        get { defaults.stringArray(forKey: Self.storesKey).map(Set.init) }
        set { defaults.set(newValue.map { Array($0).sorted() }, forKey: Self.storesKey) }
    }

    /// The stores alerts are for: the user's choice, else the stores within 2 km, else every store with offers.
    func storeIDs(for stores: [StoreSchedule], nearbyChains: Set<String>?) -> Set<String> {
        if let chosen = chosenStoreIDs { return chosen }
        let withOffers = stores.filter(\.fetchesOffers)
        guard let nearbyChains else { return Set(withOffers.map(\.id)) }
        let near = withOffers.filter { nearbyChains.contains($0.name) }
        return Set((near.isEmpty ? withOffers : near).map(\.id))
    }

    /// Asks for permission to show notifications. Returns whether it was granted.
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces the scheduled offer alerts with weekly ones for `stores` (none when alerts are off).
    func reschedule(stores: [StoreSchedule], nearbyChains: Set<String>?) async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(OfferAlert.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isEnabled else { return }
        for alert in OfferAlert.alerts(for: stores, enabled: storeIDs(for: stores, nearbyChains: nearbyChains)) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.userInfo = ["storeName": alert.storeName]
            var when = DateComponents()
            when.weekday = alert.weekday
            when.hour = OfferAlert.hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: alert.identifier, content: content, trigger: trigger))
        }
    }
}

/// Shows offer alerts while the app is open, and opens the Offers tab when one is tapped.
final class OfferAlertDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = OfferAlertDelegate()
    static let openOffers = Notification.Name("OfferAlertDelegate.openOffers")

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier.hasPrefix(OfferAlert.identifierPrefix) else { return }
        await MainActor.run { NotificationCenter.default.post(name: Self.openOffers, object: nil) }
    }
}
