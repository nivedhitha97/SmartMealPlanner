//
//  GroceryDataService.swift
//  SmartMealPlanner
//
//  Live supermarket offers and ingredient prices, exported from the grocery database that
//  scripts/grocery_db keeps up to date: each supermarket is fetched on the day its offer week starts
//  (see .github/workflows/grocery-feed.yml).
//

import Foundation

/// Where a `GroceryData` value came from.
enum GroceryDataSource: String, Codable {
    /// Downloaded just now.
    case live
    /// The last successful download, used while offline.
    case cached
    /// The sample offers bundled with the app, used when nothing was ever downloaded.
    case bundled
}

/// When a supermarket's data is refreshed, from the feed's meta.json.
struct StoreSchedule: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    /// The day the store starts its offer week and is fetched, e.g. "Wednesday".
    let updateDay: String
    /// Whether offers come from the store itself (otherwise only shelf prices).
    let fetchesOffers: Bool
    let lastUpdatedAt: Date?
    let nextUpdateAt: Date?
    /// Last time any of the store's shelf prices changed; nil if not in the last month.
    let pricesChangedAt: Date?
    /// Whether the store's shelf prices are recent enough to use; nil if it has none.
    let pricesAreCurrent: Bool?
    let lastError: String?
}

/// Offers and ingredient prices the Offers screen and the planner work with.
struct GroceryData {
    var offers: [SupermarketOffer]
    var prices: [IngredientPrice]
    /// When the feed was built; nil for bundled data.
    var updatedAt: Date?
    var source: GroceryDataSource
    /// The next time any supermarket is due to be refreshed; until then there is nothing new to download.
    var nextUpdateAt: Date? = nil
    var stores: [StoreSchedule] = []

    /// Price for a recipe ingredient, matched case-insensitively by name.
    func price(forIngredient name: String) -> IngredientPrice? {
        prices.first { $0.ingredientName.caseInsensitiveCompare(name) == .orderedSame }
    }
}

protocol GroceryDataService: AnyObject {
    /// The latest grocery data. Never fails: falls back to the cached feed, then to the bundled offers.
    /// - Parameter forceRefresh: download again even if the last download is recent.
    func latest(forceRefresh: Bool) async -> GroceryData
}

extension GroceryDataService {
    func latest() async -> GroceryData {
        await latest(forceRefresh: false)
    }
}

enum GroceryDataServices {
    /// The service the app uses. UI tests launch with `-uiTestingBundledData` to get fixed, offline data.
    static let shared: GroceryDataService = LaunchArguments.contains(LaunchArguments.bundledData)
        ? BundledGroceryDataService()
        : RemoteGroceryDataService()

    /// The stores' offer days as the grocery database found them, for use before the live schedule has loaded.
    static let defaultStoreSchedules: [StoreSchedule] = [
        ("dekamarkt", "DekaMarkt", "Tuesday"), ("dirk", "Dirk", "Wednesday"), ("hoogvliet", "Hoogvliet", "Wednesday"),
        ("jumbo", "Jumbo", "Wednesday"), ("lidl", "Lidl", "Monday"), ("poiesz", "Poiesz", "Sunday"),
    ].map { id, name, day in
        StoreSchedule(id: id, name: name, updateDay: day, fetchesOffers: true, lastUpdatedAt: nil, nextUpdateAt: nil,
                      pricesChangedAt: nil, pricesAreCurrent: nil, lastError: nil)
    }

    /// The sample offers in Data/offers.json.
    static func bundledOffers() -> [SupermarketOffer] {
        (try? JSONLoader.load("offers", as: [SupermarketOffer].self)) ?? []
    }
}

/// Only the bundled sample offers, with no ingredient prices.
final class BundledGroceryDataService: GroceryDataService {
    func latest(forceRefresh: Bool) async -> GroceryData {
        GroceryData(offers: GroceryDataServices.bundledOffers(), prices: [], updatedAt: nil, source: .bundled,
                    stores: GroceryDataServices.defaultStoreSchedules)
    }
}

/// Downloads the feed only when it can have changed. Supermarkets are refreshed once a week each, and the
/// feed says when the next refresh is due (`nextUpdateAt`); until then the copy on disk is used without any
/// request. After that, only the small meta.json is checked, and offers and prices are downloaded only if
/// the feed was actually rebuilt. The last good copy is also the offline fallback.
final class RemoteGroceryDataService: GroceryDataService {

    static let publishedFeedURL = URL(string: "https://raw.githubusercontent.com/nivedhitha97/SmartMealPlanner/grocery-feed/")!

    /// The published feed, unless the `GroceryFeedBaseURL` default points elsewhere (e.g. a self-hosted copy,
    /// or `-GroceryFeedBaseURL http://localhost:8000/` as a launch argument while developing).
    static var defaultBaseURL: URL {
        UserDefaults.standard.string(forKey: "GroceryFeedBaseURL").flatMap(URL.init(string:)) ?? publishedFeedURL
    }
    static let feedFiles = ["offers.json", "prices.json", "meta.json"]

    enum FeedError: Error {
        case badResponse(String, Int)
    }

    private struct Meta: Decodable {
        let generatedAt: Date
        let nextUpdateAt: Date?
        let stores: [StoreSchedule]?
    }

    private let baseURL: URL
    private let session: URLSession
    private let cacheDirectory: URL
    private let reuseInterval: TimeInterval
    private let now: () -> Date
    private let bundledOffers: () -> [SupermarketOffer]
    private var lastCheck: (data: GroceryData, at: Date)?
    /// Requests made by this service, for tests and diagnostics.
    private(set) var requestCount = 0

    init(
        baseURL: URL = RemoteGroceryDataService.defaultBaseURL,
        session: URLSession = .shared,
        cacheDirectory: URL = URL.cachesDirectory.appending(path: "GroceryFeed", directoryHint: .isDirectory),
        reuseInterval: TimeInterval = 10 * 60,
        now: @escaping () -> Date = Date.init,
        bundledOffers: @escaping () -> [SupermarketOffer] = GroceryDataServices.bundledOffers
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cacheDirectory = cacheDirectory
        self.reuseInterval = reuseInterval
        self.now = now
        self.bundledOffers = bundledOffers
    }

    func latest(forceRefresh: Bool) async -> GroceryData {
        // What this service last returned is reused from memory while it is still current, so opening the Offers
        // or Settings tab doesn't read and decode the whole feed from disk every time.
        if !forceRefresh, let lastCheck {
            if lastCheck.data.source == .live, let next = lastCheck.data.nextUpdateAt, now() < next {
                return lastCheck.data
            }
            if now().timeIntervalSince(lastCheck.at) < reuseInterval {
                return lastCheck.data
            }
        }
        let cached = loadFromCache()
        if !forceRefresh {
            // Nothing new is published before the next store refresh.
            if let cached, let next = cached.nextUpdateAt, now() < next {
                return remember(cached)
            }
            // Past it, check at most every few minutes.
            if let lastCheck, now().timeIntervalSince(lastCheck.at) < reuseInterval {
                return lastCheck.data
            }
        }
        do {
            let metaData = try await download("meta.json")
            let meta = try Self.decoder.decode(Meta.self, from: metaData)
            if let cached, cached.updatedAt == meta.generatedAt {
                // Not rebuilt yet (the store hasn't published its new week): keep the copy, with the new schedule.
                saveToCache(["meta.json": metaData])
                return remember(try Self.decode(cachedFiles(replacing: metaData), source: .live))
            }
            async let offers = download("offers.json")
            async let prices = download("prices.json")
            let files = try await ["offers.json": offers, "prices.json": prices, "meta.json": metaData]
            let data = try Self.decode(files, source: .live)
            saveToCache(files)
            return remember(data)
        } catch {
            if let cached { return GroceryData(offers: cached.offers, prices: cached.prices, updatedAt: cached.updatedAt,
                                               source: .cached, nextUpdateAt: cached.nextUpdateAt, stores: cached.stores) }
            return GroceryData(offers: bundledOffers(), prices: [], updatedAt: nil, source: .bundled)
        }
    }

    private func remember(_ data: GroceryData) -> GroceryData {
        lastCheck = (data, now())
        return data
    }

    private func download(_ file: String) async throws -> Data {
        requestCount += 1
        let request = URLRequest(url: baseURL.appending(path: file), cachePolicy: .reloadRevalidatingCacheData,
                                 timeoutInterval: 15)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FeedError.badResponse(file, status) }
        return data
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func decode(_ files: [String: Data], source: GroceryDataSource) throws -> GroceryData {
        let meta = try decoder.decode(Meta.self, from: files["meta.json"] ?? Data())
        return GroceryData(
            offers: try decoder.decode([SupermarketOffer].self, from: files["offers.json"] ?? Data()),
            prices: try decoder.decode([IngredientPrice].self, from: files["prices.json"] ?? Data()),
            updatedAt: meta.generatedAt,
            source: source,
            nextUpdateAt: meta.nextUpdateAt,
            stores: meta.stores ?? []
        )
    }

    // MARK: - Disk cache

    private func saveToCache(_ files: [String: Data]) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        for (name, data) in files {
            try? data.write(to: cacheDirectory.appending(path: name), options: .atomic)
        }
    }

    /// The copy on disk. It is current until its `nextUpdateAt`, so it is returned as live data.
    private func loadFromCache() -> GroceryData? {
        try? Self.decode(cachedFiles(), source: .live)
    }

    private func cachedFiles(replacing meta: Data? = nil) -> [String: Data] {
        var files: [String: Data] = [:]
        for name in Self.feedFiles {
            files[name] = try? Data(contentsOf: cacheDirectory.appending(path: name))
        }
        if let meta { files["meta.json"] = meta }
        return files
    }
}
