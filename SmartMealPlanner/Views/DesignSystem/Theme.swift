//
//  Theme.swift
//  SmartMealPlanner
//
//  Design tokens and shared components. Mirrors the "Color" variable collection and
//  component library in the Figma file "Smart Meal Planner – UI Revamp".
//

import SwiftUI
import UIKit

// MARK: - Color tokens

extension Color {
    private static func token(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    static let bgCanvas = token(0xF7F5F0, 0x121614)
    static let bgSurface = token(0xFFFFFF, 0x1B201D)
    static let bgMuted = token(0xEFECE5, 0x262C28)

    static let brandPrimary = token(0x2E7D5B, 0x4FA97F)
    static let brandPrimarySoft = token(0xE3F1EA, 0x1E3329)
    static let brandPrimaryDeep = token(0x1F5A41, 0x8FD3B0)

    static let accentCoral = token(0xF0684A, 0xF27E62)
    static let accentCoralSoft = token(0xFDE9E3, 0x3A2420)
    static let accentAmber = token(0xE9A23B, 0xF0B456)
    static let accentAmberSoft = token(0xFCF1DE, 0x3A2E1A)

    static let textPrimary = token(0x1C2621, 0xEEF2EF)
    static let textSecondary = token(0x69766F, 0xA1ADA6)
    static let textTertiary = token(0xA3ADA7, 0x6B766F)

    static let borderSubtle = token(0xE6E2DA, 0x2C332F)
}

// MARK: - Typography

extension Font {
    static let screenTitle = Font.system(size: 34, weight: .bold)
    static let sectionTitle = Font.system(size: 22, weight: .bold)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        modifier(CardModifier(padding: padding, radius: radius))
    }

    /// Canvas background plus a scrim under the status bar, for screens that hide the nav bar
    /// and draw their own header.
    func screenBackground() -> some View {
        background(Color.bgCanvas.ignoresSafeArea())
            .toolbarBackground(Color.bgCanvas, for: .navigationBar)
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [.init(color: .bgCanvas, location: 0.6), .init(color: .bgCanvas.opacity(0), location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.safeAreaInsets.top + 12)
                    .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Fades the canvas in behind a button pinned with `safeAreaInset(edge: .bottom)`.
    func floatingBarBackground() -> some View {
        background(
            LinearGradient(
                stops: [.init(color: .bgCanvas.opacity(0), location: 0), .init(color: .bgCanvas, location: 0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -24)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }
}

// MARK: - Headers

struct ScreenHeader<Trailing: View>: View {
    var eyebrow: String?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                Text(title)
                    .font(.screenTitle)
                    .tracking(-0.6)
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sectionTitle)
                    .tracking(-0.3)
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Card header with a tinted icon tile, used by Preferences and Meal Routine.
struct CardHeader<Trailing: View>: View {
    let icon: String
    let tint: Color
    let tintBackground: Color
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, tint: tint, background: tintBackground)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Color.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(icon: String, tint: Color, tintBackground: Color, title: String, subtitle: String? = nil) {
        self.init(icon: icon, tint: tint, tintBackground: tintBackground, title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Small components

struct IconTile: View {
    let systemName: String
    let tint: Color
    let background: Color
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct IconCircle: View {
    let systemName: String
    let tint: Color
    let background: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: Circle())
    }
}

/// Selectable pill. Matches the Figma "Chip" component (Selected=true/false).
struct Chip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
            .background(isSelected ? Color.brandPrimary : Color.bgSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.borderSubtle, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small tinted label, e.g. "Within budget", "−23%", store deal badges.
struct Badge: View {
    let text: String
    var systemImage: String?
    var foreground: Color
    var background: Color

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isSecondary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isSecondary ? Color.brandPrimaryDeep : Color.white)
            .background(
                isSecondary ? Color.brandPrimarySoft : Color.brandPrimary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var secondary: PrimaryButtonStyle { PrimaryButtonStyle(isSecondary: true) }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }
}

// MARK: - Food imagery

/// Warm gradients used as image placeholders, keyed so the same recipe always gets the same one.
enum FoodGradient: CaseIterable {
    case amber, green, coral, plum

    var colors: [Color] {
        switch self {
        case .amber: return [Color(red: 0.97, green: 0.78, blue: 0.45), Color(red: 0.90, green: 0.60, blue: 0.23)]
        case .green: return [Color(red: 0.66, green: 0.84, blue: 0.64), Color(red: 0.25, green: 0.56, blue: 0.39)]
        case .coral: return [Color(red: 0.96, green: 0.65, blue: 0.55), Color(red: 0.88, green: 0.35, blue: 0.24)]
        case .plum: return [Color(red: 0.79, green: 0.71, blue: 0.92), Color(red: 0.49, green: 0.39, blue: 0.75)]
        }
    }

    static func forKey(_ key: String) -> FoodGradient {
        let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return allCases[sum % allCases.count]
    }
}

/// Recipe photo with a gradient fallback while loading or when no URL exists.
struct RecipeImage: View {
    let url: URL?
    let placeholderKey: String
    var iconSize: CGFloat = 22

    var body: some View {
        ZStack {
            LinearGradient(
                colors: FoodGradient.forKey(placeholderKey).colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
            }
        }
        .clipped()
    }
}

// MARK: - Layout

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, maxWidth: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    /// Ideal size, but never wider than a full line so long items wrap instead of overflowing.
    private static func size(of view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

// MARK: - Formatting

extension Double {
    var euros: String {
        "€" + formatted(.number.precision(.fractionLength(2)))
    }

    var eurosRounded: String {
        "€" + formatted(.number.precision(.fractionLength(0)))
    }
}
