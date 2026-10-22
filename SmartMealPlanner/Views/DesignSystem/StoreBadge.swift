//
//  StoreBadge.swift
//  SmartMealPlanner
//
//  Store badges: the supermarket's real logo where a public-domain version exists (from Wikimedia Commons, bundled in
//  Assets.xcassets/StoreLogos; see docs/DESIGN.md), else a monogram in the store's brand colours. The logos only
//  identify which store an offer is from.
//

import SwiftUI

struct StoreBrand: Equatable {
    let monogram: String
    let background: Color
    let foreground: Color
    /// The logo in Assets.xcassets/StoreLogos and its width ÷ height; nil when there is no public-domain logo.
    var logo: (asset: String, aspect: CGFloat)? = nil

    static func == (lhs: StoreBrand, rhs: StoreBrand) -> Bool {
        lhs.monogram == rhs.monogram && lhs.background == rhs.background && lhs.foreground == rhs.foreground
            && lhs.logo?.asset == rhs.logo?.asset
    }

    private static let brands: [String: StoreBrand] = [
        "albert heijn": StoreBrand(monogram: "AH", background: Color(hex: 0x00A0E2), foreground: .white,
                                   logo: ("logo-ah", 0.96)),
        "jumbo": StoreBrand(monogram: "J", background: Color(hex: 0xFFD200), foreground: Color(hex: 0x1D1D1B),
                            logo: ("logo-jumbo", 3.58)),
        "lidl": StoreBrand(monogram: "L", background: Color(hex: 0x0050AA), foreground: Color(hex: 0xFFF000),
                           logo: ("logo-lidl", 1.0)),
        "dirk": StoreBrand(monogram: "D", background: Color(hex: 0xE30613), foreground: .white, logo: ("logo-dirk", 1.47)),
        "dekamarkt": StoreBrand(monogram: "DM", background: Color(hex: 0xD7141A), foreground: Color(hex: 0xFFE500),
                                logo: ("logo-dekamarkt", 2.3)),
        "hoogvliet": StoreBrand(monogram: "H", background: Color(hex: 0xE3051B), foreground: .white,
                                logo: ("logo-hoogvliet", 3.14)),
        // No public-domain logo found for Poiesz or Plus: their monograms stay.
        "poiesz": StoreBrand(monogram: "P", background: Color(hex: 0xC8102E), foreground: .white),
        "plus": StoreBrand(monogram: "P+", background: Color(hex: 0x00A651), foreground: .white),
        "spar": StoreBrand(monogram: "S", background: Color(hex: 0x00843D), foreground: .white, logo: ("logo-spar", 6.29)),
        "vomar": StoreBrand(monogram: "V", background: Color(hex: 0xE2001A), foreground: .white, logo: ("logo-vomar", 2.07)),
        "aldi": StoreBrand(monogram: "A", background: Color(hex: 0x00005F), foreground: .white, logo: ("logo-aldi", 0.96)),
    ]

    /// The brand for a store name (case-insensitive); unknown stores get neutral initials.
    static func forStore(_ name: String) -> StoreBrand {
        if let brand = brands[name.lowercased()] { return brand }
        let initials = String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
        return StoreBrand(monogram: initials.isEmpty ? "?" : initials, background: .bgMuted, foreground: .textSecondary)
    }

    static var knownStores: Int { brands.count }
}

/// A store's badge, e.g. in filter chips and list headings: its logo on a white tile, as wide as the logo needs
/// (wordmarks like Jumbo's up to 2.6× the height), or its monogram.
struct StoreBadge: View {
    let store: String
    var size: CGFloat = 20

    static let maxAspect: CGFloat = 2.6

    /// For lists: the widest a badge can be, so names after badges of any width line up.
    static func columnWidth(size: CGFloat) -> CGFloat { size * maxAspect }

    /// The tile's width for this store at a given height.
    static func width(for store: String, size: CGFloat) -> CGFloat {
        guard let logo = StoreBrand.forStore(store).logo else { return size }
        return size * min(max(logo.aspect, 1), maxAspect)
    }

    var body: some View {
        let brand = StoreBrand.forStore(store)
        if let logo = brand.logo {
            // Logos are made for a white background, so the tile stays white in dark mode too.
            Image(logo.asset)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.1)
                .frame(width: Self.width(for: store, size: size), height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                .accessibilityHidden(true)
        } else {
            monogram(brand)
        }
    }

    private func monogram(_ brand: StoreBrand) -> some View {
        Text(brand.monogram)
            .font(.system(size: size * (brand.monogram.count > 1 ? 0.42 : 0.55), weight: .heavy, design: .rounded))
            .foregroundStyle(brand.foreground)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(brand.background, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A filter chip for a store: its logo in place of the name (VoiceOver reads the name).
struct StoreChip: View {
    let store: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            StoreBadge(store: store, size: 26)
                .padding(5)
                .background(isSelected ? Color.brandPrimarySoft : Color.bgSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Color.brandPrimary : Color.borderSubtle,
                                                lineWidth: isSelected ? 2 : 1))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityLabel(store)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    /// A colour from a 0xRRGGBB value.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
