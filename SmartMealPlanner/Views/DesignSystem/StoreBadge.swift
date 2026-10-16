//
//  StoreBadge.swift
//  SmartMealPlanner
//
//  Store badges: a monogram in each supermarket's brand colours. Drawn by the app, so there's no logo artwork to
//  license, nothing to download and nothing a store can block.
//

import SwiftUI

struct StoreBrand: Equatable {
    let monogram: String
    let background: Color
    let foreground: Color

    private static let brands: [String: StoreBrand] = [
        "albert heijn": StoreBrand(monogram: "AH", background: Color(hex: 0x00A0E2), foreground: .white),
        "jumbo": StoreBrand(monogram: "J", background: Color(hex: 0xFFD200), foreground: Color(hex: 0x1D1D1B)),
        "lidl": StoreBrand(monogram: "L", background: Color(hex: 0x0050AA), foreground: Color(hex: 0xFFF000)),
        "dirk": StoreBrand(monogram: "D", background: Color(hex: 0xE30613), foreground: .white),
        "dekamarkt": StoreBrand(monogram: "DM", background: Color(hex: 0xD7141A), foreground: Color(hex: 0xFFE500)),
        "hoogvliet": StoreBrand(monogram: "H", background: Color(hex: 0xE3051B), foreground: .white),
        "poiesz": StoreBrand(monogram: "P", background: Color(hex: 0xC8102E), foreground: .white),
        "plus": StoreBrand(monogram: "P+", background: Color(hex: 0x00A651), foreground: .white),
        "spar": StoreBrand(monogram: "S", background: Color(hex: 0x00843D), foreground: .white),
        "vomar": StoreBrand(monogram: "V", background: Color(hex: 0xE2001A), foreground: .white),
        "aldi": StoreBrand(monogram: "A", background: Color(hex: 0x00005F), foreground: .white),
    ]

    /// The brand for a store name (case-insensitive); unknown stores get neutral initials.
    static func forStore(_ name: String) -> StoreBrand {
        if let brand = brands[name.lowercased()] { return brand }
        let initials = String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
        return StoreBrand(monogram: initials.isEmpty ? "?" : initials, background: .bgMuted, foreground: .textSecondary)
    }

    static var knownStores: Int { brands.count }
}

/// A store's monogram badge, e.g. in filter chips and list headings.
struct StoreBadge: View {
    let store: String
    var size: CGFloat = 20

    var body: some View {
        let brand = StoreBrand.forStore(store)
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

/// A filter chip for a store: its badge and name.
struct StoreChip: View {
    let store: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                StoreBadge(store: store, size: 20)
                Text(store)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
            }
            .padding(.vertical, 7)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
            .background(isSelected ? Color.brandPrimary : Color.bgSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.borderSubtle, lineWidth: 1))
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
