//
//  PostcodeLocationService.swift
//  SmartMealPlanner
//
//  Turns a Dutch postcode into the shopping location used to match regional offers.
//

import Foundation
import MapKit

/// Location derived from a postcode.
struct PostcodeLocation: Equatable {
    /// Normalized postcode, e.g. "1012 AB".
    let postcode: String
    /// City from the geocoder; nil when offline or not found.
    let city: String?
    /// Offer region derived from the postcode, e.g. "NL-North".
    let regionId: String
    /// Where the postcode is (street level for a full postcode); nil when offline.
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// Supermarkets within `NearbyStores.radiusMeters`, nearest first; empty when unknown.
    var nearbyStores: [NearbyStore] = []

    /// Stored as `UserPreferences.shoppingRegion`. The planner matches an offer when this string
    /// contains the offer's `regionId`, so including both city and region matches city-specific
    /// and regional flyers.
    var shoppingRegion: String {
        [city, regionId].compactMap { $0 }.joined(separator: ", ")
    }
}

enum PostcodeLookupError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Enter a Dutch postcode, e.g. 1012 AB."
        }
    }
}

enum PostcodeLocationService {

    /// Normalizes "1012ab" / "1012 AB" to "1012 AB", or a bare "1012" to "1012". Returns nil if it isn't a Dutch postcode.
    static func normalize(_ raw: String) -> String? {
        let compact = raw.uppercased().filter { !$0.isWhitespace }
        guard compact.count == 4 || compact.count == 6 else { return nil }
        let digits = compact.prefix(4)
        let letters = compact.dropFirst(4)
        guard digits.first != "0",
              digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              letters.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }
        return letters.isEmpty ? String(digits) : "\(digits) \(letters)"
    }

    /// Offer region for a postcode, based on the first digit of the Dutch postcode system
    /// (postcodes are assigned geographically, roughly north-west to south-east).
    static func regionId(forPostcode postcode: String) -> String {
        switch postcode.first {
        case "1", "8", "9": return "NL-North"   // Noord-Holland, Flevoland, Friesland, Groningen, Drenthe
        case "2", "3": return "NL-West"         // Zuid-Holland, Utrecht
        case "7": return "NL-East"              // Overijssel, Gelderland (east)
        default: return "NL-South"              // Zeeland, Noord-Brabant, Limburg, Gelderland (south)
        }
    }

    /// Resolves a postcode to a location: its region (from the postcode itself), and online its city, exact
    /// position and the supermarkets within 2 km. Online parts are left empty if the lookup fails, so this only
    /// throws for a malformed postcode.
    static func resolve(_ raw: String) async throws -> PostcodeLocation {
        guard let postcode = normalize(raw) else { throw PostcodeLookupError.invalidFormat }
        let region = regionId(forPostcode: postcode)
        guard let request = MKGeocodingRequest(addressString: "\(postcode), Netherlands"),
              let item = try? await request.mapItems.first else {
            return PostcodeLocation(postcode: postcode, city: nil, regionId: region)
        }
        let coordinate = item.location.coordinate
        return PostcodeLocation(postcode: postcode, city: item.addressRepresentations?.cityName, regionId: region,
                                latitude: coordinate.latitude, longitude: coordinate.longitude,
                                nearbyStores: await NearbyStores.search(around: coordinate))
    }
}
