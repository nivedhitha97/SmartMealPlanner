//
//  StoreBadge.swift
//  SmartMealPlanner
//
//  Store badges: the store's initials in the app's own neutral colours. No supermarket logos or brand colours are
//  used: the app is not affiliated with any supermarket, and store names only say where an offer is from.
//

import SwiftUI

struct StoreBrand: Equatable {
    let monogram: String

    /// Initials for well-known names that aren't simply their words' first letters.
    private static let monograms: [String: String] = ["albert heijn": "AH", "dekamarkt": "DM", "plus": "P+"]

    /// The badge for a store name (case-insensitive): its initials.
    static func forStore(_ name: String) -> StoreBrand {
        if let monogram = monograms[name.lowercased()] { return StoreBrand(monogram: monogram) }
        let initials = String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
        return StoreBrand(monogram: initials.isEmpty ? "?" : initials)
    }
}

/// A store's badge, e.g. in list headings: its initials on a neutral square tile.
struct StoreBadge: View {
    let store: String
    var size: CGFloat = 20

    /// For lists: the badge's width, so names after badges line up.
    static func columnWidth(size: CGFloat) -> CGFloat { size }

    var body: some View {
        let brand = StoreBrand.forStore(store)
        Text(brand.monogram)
            .font(.system(size: size * (brand.monogram.count > 1 ? 0.42 : 0.55), weight: .heavy, design: .rounded))
            .foregroundStyle(Color.brandPrimaryDeep)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(Color.brandPrimarySoft, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
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
            HStack(spacing: 6) {
                StoreBadge(store: store, size: 22)
                Text(store)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.brandPrimaryDeep : Color.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(isSelected ? Color.brandPrimarySoft : Color.bgSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.brandPrimary : Color.borderSubtle,
                                            lineWidth: isSelected ? 2 : 1))
            .frame(minHeight: 44)
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
