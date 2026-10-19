//
//  NearbyStoresService.swift
//  SmartMealPlanner
//
//  Supermarkets within walking/cycling distance of the user's postcode, from Apple Maps (no API key, free).
//

import CoreLocation
import Foundation
import MapKit

/// A supermarket branch near the user's postcode.
struct NearbyStore: Codable, Hashable, Identifiable {
    var id: String { "\(chain)|\(latitude)|\(longitude)" }
    /// The chain as the app's offers name it, e.g. "Albert Heijn".
    let chain: String
    /// The branch's own name, e.g. "Albert Heijn Bos en Lommerweg".
    let branchName: String
    let distanceMeters: Double
    let latitude: Double
    let longitude: Double

    /// "350 m", "1.2 km".
    var distanceText: String { NearbyStores.distanceText(distanceMeters) }
}

enum NearbyStores {

    /// Only stores this close to the postcode count as nearby.
    static let radiusMeters: Double = 2_000

    /// Branch-name patterns for each chain the app has offers or prices for.
    private static let chains: [(chain: String, patterns: [String])] = [
        ("Albert Heijn", ["albert heijn", "ah to go", "ah xl"]),
        ("Jumbo", ["jumbo"]),
        ("Lidl", ["lidl"]),
        ("Dirk", ["dirk"]),
        ("DekaMarkt", ["dekamarkt", "deka markt"]),
        ("Hoogvliet", ["hoogvliet"]),
        ("Poiesz", ["poiesz"]),
        ("Plus", ["plus"]),
        ("Spar", ["spar"]),
        ("Vomar", ["vomar"]),
        ("Aldi", ["aldi"]),
    ]

    /// The chain a place belongs to, from its name (whole words, so "PLUS Bos en Lommer" is Plus but
    /// "Sparkling" isn't Spar); nil for shops the app has no data for.
    static func chain(forPlaceName name: String) -> String? {
        let words = " " + String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }) + " "
        return chains.first { entry in entry.patterns.contains { words.contains(" \($0) ") } }?.chain
    }

    /// Stores within `radiusMeters`, nearest first, from places found around `center`.
    static func stores(from places: [(name: String, coordinate: CLLocationCoordinate2D)],
                       around center: CLLocationCoordinate2D) -> [NearbyStore] {
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return places.compactMap { place -> NearbyStore? in
            guard let chain = chain(forPlaceName: place.name) else { return nil }
            let distance = origin.distance(from: CLLocation(latitude: place.coordinate.latitude,
                                                            longitude: place.coordinate.longitude))
            guard distance <= radiusMeters else { return nil }
            return NearbyStore(chain: chain, branchName: place.name, distanceMeters: distance,
                               latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// The nearest branch of each chain, nearest first.
    static func nearestPerChain(_ stores: [NearbyStore]) -> [NearbyStore] {
        var seen = Set<String>()
        return stores.sorted { $0.distanceMeters < $1.distanceMeters }.filter { seen.insert($0.chain).inserted }
    }

    static func distanceText(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int((meters / 50).rounded() * 50)) m"
            : String(format: "%.1f km", meters / 1_000).replacingOccurrences(of: ".0 km", with: " km")
    }

    /// Supermarkets within 2 km of `center` from Apple Maps; empty if the search fails (e.g. offline).
    /// Apple's general "nearby" search returns only a limited set of places, so each chain is also searched for
    /// by name in the same area, and the results are merged.
    static func search(around center: CLLocationCoordinate2D) async -> [NearbyStore] {
        let names = chains.map(\.chain)
        let found = await withTaskGroup(of: [(name: String, coordinate: CLLocationCoordinate2D)].self) { group in
            group.addTask { await pointsOfInterest(around: center) }
            for name in names {
                group.addTask { await places(named: name, around: center) }
            }
            var all: [(name: String, coordinate: CLLocationCoordinate2D)] = []
            for await found in group { all += found }
            return all
        }
        return deduplicated(stores(from: found, around: center))
    }

    /// The same branch found by several searches counts once (same chain within 30 m).
    static func deduplicated(_ stores: [NearbyStore]) -> [NearbyStore] {
        var kept: [NearbyStore] = []
        for store in stores where !kept.contains(where: { other in
            other.chain == store.chain
                && CLLocation(latitude: other.latitude, longitude: other.longitude)
                    .distance(from: CLLocation(latitude: store.latitude, longitude: store.longitude)) < 30
        }) {
            kept.append(store)
        }
        return kept
    }

    private static func pointsOfInterest(around center: CLLocationCoordinate2D) async -> [(name: String, coordinate: CLLocationCoordinate2D)] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket, .store])
        return places(from: try? await MKLocalSearch(request: request).start())
    }

    private static func places(named query: String, around center: CLLocationCoordinate2D) async -> [(name: String, coordinate: CLLocationCoordinate2D)] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: radiusMeters * 2,
                                            longitudinalMeters: radiusMeters * 2)
        request.resultTypes = .pointOfInterest
        return places(from: try? await MKLocalSearch(request: request).start())
    }

    private static func places(from response: MKLocalSearch.Response?) -> [(name: String, coordinate: CLLocationCoordinate2D)] {
        (response?.mapItems ?? []).compactMap { item in
            guard let name = item.name else { return nil }
            return (name, item.location.coordinate)
        }
    }
}
