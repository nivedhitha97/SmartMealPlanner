//
//  GroceryDataServiceTests.swift
//  SmartMealPlannerTests
//
//  The live grocery feed: downloading only when the feed can have changed, caching for offline use, and
//  falling back to the bundled offers.
//  Network calls go to a stub URL protocol, so these tests never touch the internet.
//

import Foundation
import Testing
@testable import SmartMealPlanner

/// Answers requests from a table of canned responses, keyed by file name ("offers.json"), and counts requests.
nonisolated final class StubURLProtocol: URLProtocol {

    struct Response {
        var status: Int
        var body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]
    nonisolated(unsafe) private static var requests = 0

    static func set(_ newResponses: [String: Response]) {
        lock.withLock { responses = newResponses; requests = 0 }
    }

    static var requestCount: Int { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let file = request.url?.lastPathComponent ?? ""
        let response = Self.lock.withLock {
            Self.requests += 1
            return Self.responses[file]
        }
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// The stub's responses are global, so these tests run one at a time.
@MainActor
@Suite("Live grocery data", .serialized)
struct GroceryDataServiceTests {

    private let cacheDirectory = FileManager.default.temporaryDirectory
        .appending(path: "GroceryFeedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private let bundled = [Fixtures.offer(product: "Bundled Broccoli", price: 1.49)]

    private static let offersJSON = """
    [{
      "id": "D5BC823C-AC80-5989-AC1B-BADA12E0B6A9", "storeName": "Spar", "productName": "Broccoli",
      "category": "Produce", "offerPrice": 0.99, "regularPrice": 1.49, "unitLabel": "500 Gram",
      "validUntil": "2026-10-22T06:30:00Z", "observedAt": "2026-10-15T06:30:00Z", "regionId": "NL",
      "notes": "Was €1.49 in the last two weeks", "ingredientName": "Broccoli", "dealText": "1+1 gratis",
      "imageURL": "https://static.hoogvliet.nl/ecom/product/719501000.jpg"
    }]
    """
    private static let pricesJSON = """
    [{
      "ingredientName": "Rice", "pricePer100g": 0.19, "cheapestStore": "DekaMarkt",
      "cheapestProduct": "G'woon Witte rijst", "cheapestPrice": 1.19, "cheapestSize": "1 kg",
      "cheapestPricePer100g": 0.119, "storeCount": 8, "productCount": 110
    }]
    """
    private static let metaJSON = #"{"generatedAt": "2026-10-15T06:30:00Z", "source": "test"}"#

    /// meta.json for a feed built at `generatedAt` whose next store refresh is `nextUpdateAt`.
    private static func scheduledMeta(generatedAt: String = "2026-10-15T06:30:00Z", nextUpdateAt: String) -> String {
        """
        {"generatedAt": "\(generatedAt)", "nextUpdateAt": "\(nextUpdateAt)", "stores": [{
          "id": "poiesz", "name": "Poiesz", "updateDay": "Sunday", "fetchesOffers": true,
          "lastUpdatedAt": "2026-10-11T04:15:00Z", "nextUpdateAt": "\(nextUpdateAt)",
          "pricesChangedAt": "2026-10-11T04:15:00Z", "pricesAreCurrent": true, "lastError": null
        }]}
        """
    }

    private static func feed(offers: String = offersJSON, meta: String = metaJSON,
                             status: Int = 200) -> [String: StubURLProtocol.Response] {
        [
            "offers.json": .init(status: status, body: Data(offers.utf8)),
            "prices.json": .init(status: status, body: Data(pricesJSON.utf8)),
            "meta.json": .init(status: status, body: Data(meta.utf8)),
        ]
    }

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func makeService(now: @escaping () -> Date = Date.init) -> RemoteGroceryDataService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let bundled = self.bundled
        return RemoteGroceryDataService(
            baseURL: URL(string: "https://feed.test/grocery-feed/")!,
            session: URLSession(configuration: configuration),
            cacheDirectory: cacheDirectory,
            now: now,
            bundledOffers: { bundled }
        )
    }

    // MARK: - Downloading

    @Test func downloadsOffersPricesAndUpdateTime() async throws {
        StubURLProtocol.set(Self.feed())

        let data = await makeService().latest()

        #expect(data.source == .live)
        let offer = try #require(data.offers.first)
        #expect(offer.productName == "Broccoli")
        #expect(offer.offerPrice == 0.99)
        #expect(offer.regionId == SupermarketOffer.nationalRegionId)
        #expect(offer.ingredientName == "Broccoli")
        #expect(offer.isLivePriceDrop)
        #expect(offer.dealText == "1+1 gratis")
        #expect(offer.imageURL == URL(string: "https://static.hoogvliet.nl/ecom/product/719501000.jpg"))
        #expect(data.price(forIngredient: "rice")?.pricePer100g == 0.19, "Ingredient lookup ignores case")
        #expect(data.updatedAt == ISO8601DateFormatter().date(from: "2026-10-15T06:30:00Z"))
    }

    @Test func recentCheckIsReusedUntilARefreshIsForced() async {
        StubURLProtocol.set(Self.feed())
        let service = makeService()

        _ = await service.latest()
        _ = await service.latest()
        #expect(StubURLProtocol.requestCount == 3, "Second call reuses the first download (3 files)")

        _ = await service.latest(forceRefresh: true)
        #expect(StubURLProtocol.requestCount == 4, "Pull to refresh checks meta.json; the feed hasn't changed")
    }

    @Test func nothingIsDownloadedBeforeTheNextStoreRefresh() async {
        StubURLProtocol.set(Self.feed(meta: Self.scheduledMeta(nextUpdateAt: "2026-10-18T04:00:00Z")))
        _ = await makeService(now: { Self.date("2026-10-15T08:00:00Z") }).latest()
        StubURLProtocol.set(Self.feed())

        // A relaunch on Saturday: Poiesz isn't refreshed until Sunday morning.
        let relaunched = makeService(now: { Self.date("2026-10-17T20:00:00Z") })
        let data = await relaunched.latest()

        #expect(relaunched.requestCount == 0)
        #expect(data.source == .live, "The saved copy is still the current feed")
        #expect(data.nextUpdateAt == Self.date("2026-10-18T04:00:00Z"))
        #expect(data.stores.map(\.name) == ["Poiesz"])
        #expect(data.stores.first?.updateDay == "Sunday")
    }

    @Test func afterTheRefreshTimeOnlyMetaIsCheckedIfTheFeedIsUnchanged() async {
        let meta = Self.scheduledMeta(nextUpdateAt: "2026-10-18T04:00:00Z")
        StubURLProtocol.set(Self.feed(meta: meta))
        _ = await makeService(now: { Self.date("2026-10-15T08:00:00Z") }).latest()

        // Sunday, but the store hasn't published yet, so the feed wasn't rebuilt.
        let service = makeService(now: { Self.date("2026-10-18T05:00:00Z") })
        let data = await service.latest()

        #expect(service.requestCount == 1, "Just meta.json")
        #expect(data.source == .live)
        #expect(data.offers.map(\.productName) == ["Broccoli"])
    }

    @Test func rebuiltFeedIsDownloaded() async {
        StubURLProtocol.set(Self.feed(meta: Self.scheduledMeta(nextUpdateAt: "2026-10-18T04:00:00Z")))
        _ = await makeService(now: { Self.date("2026-10-15T08:00:00Z") }).latest()

        let rebuilt = Self.offersJSON.replacingOccurrences(of: "\"productName\": \"Broccoli\"",
                                                           with: "\"productName\": \"Pompoen\"")
        StubURLProtocol.set(Self.feed(offers: rebuilt, meta: Self.scheduledMeta(
            generatedAt: "2026-10-18T04:20:00Z", nextUpdateAt: "2026-10-20T04:00:00Z")))
        let service = makeService(now: { Self.date("2026-10-18T05:00:00Z") })
        let data = await service.latest()

        #expect(service.requestCount == 3)
        #expect(data.offers.map(\.productName) == ["Pompoen"])
        #expect(data.nextUpdateAt == Self.date("2026-10-20T04:00:00Z"))
    }

    @Test func checkIsRepeatedOnceItIsOld() async {
        StubURLProtocol.set(Self.feed())
        var clock = Fixtures.now
        let service = makeService(now: { clock })

        _ = await service.latest()
        clock = clock.addingTimeInterval(11 * 60)
        _ = await service.latest()

        #expect(StubURLProtocol.requestCount == 4, "3 files, then meta.json again")
    }

    // MARK: - Offline

    @Test func offlineFallsBackToTheLastDownload() async {
        StubURLProtocol.set(Self.feed())
        _ = await makeService().latest()

        StubURLProtocol.set([:])  // no connection
        let data = await makeService().latest()

        #expect(data.source == .cached)
        #expect(data.offers.map(\.productName) == ["Broccoli"])
        #expect(data.prices.map(\.ingredientName) == ["Rice"])
        #expect(data.updatedAt != nil)
    }

    @Test func offlineWithoutAnyDownloadUsesTheBundledOffers() async {
        StubURLProtocol.set([:])

        let data = await makeService().latest()

        #expect(data.source == .bundled)
        #expect(data.offers.map(\.productName) == ["Bundled Broccoli"])
        #expect(data.prices.isEmpty)
        #expect(data.updatedAt == nil)
    }

    @Test func serverErrorIsTreatedAsOffline() async {
        StubURLProtocol.set(Self.feed(status: 404))

        let data = await makeService().latest()

        #expect(data.source == .bundled)
    }

    @Test func brokenFeedDoesNotReplaceTheCachedCopy() async {
        StubURLProtocol.set(Self.feed())
        _ = await makeService().latest()

        StubURLProtocol.set(Self.feed(offers: "not json", meta: #"{"generatedAt": "2026-10-16T06:30:00Z"}"#))
        let data = await makeService().latest()

        #expect(data.source == .cached)
        #expect(data.offers.map(\.productName) == ["Broccoli"])
    }

    // MARK: - Compatibility

    @Test func bundledOffersWithoutLiveFieldsStillDecode() throws {
        let offers = GroceryDataServices.bundledOffers()

        #expect(!offers.isEmpty)
        #expect(offers.allSatisfy { !$0.isLivePriceDrop && $0.ingredientName == nil && $0.dealText == nil
                                    && $0.imageURL == nil })
    }

    @Test(arguments: [
        (GroceryDataSource.live, "Live prices · updated"),
        (.cached, "Offline · prices from"),
        (.bundled, "Offline · sample offers"),
    ])
    func freshnessLineSaysWhereThePricesCameFrom(source: GroceryDataSource, prefix: String) {
        let text = OffersList.freshnessText(source: source, updatedAt: Fixtures.date(daysFromNow: -1), now: Fixtures.now)

        #expect(text.hasPrefix(prefix))
    }
}
