//
//  AppIconTests.swift
//  SmartMealPlannerTests
//
//  Checks the light, dark and tinted app icons in the asset catalog. The PNGs are read from the
//  source tree (simulator tests run on the Mac), so this doesn't run on a physical device.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SmartMealPlanner

@Suite("App icon")
struct AppIconTests {

    /// Badge position in the icon artwork (pixels from the top left), see docs/app-icon/make_icon.swift.
    private let badgeCenter = (x: 712, y: 312)
    private let badgeInnerRadius = 125.0

    private static let iconSet = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("SmartMealPlanner/Assets.xcassets/AppIcon.appiconset")

    // MARK: - Asset catalog

    @Test func assetCatalogDeclaresLightDarkAndTintedIcons() throws {
        let images = try iconEntries()

        #expect(Set(images.keys) == ["light", "dark", "tinted"])
        for (appearance, filename) in images {
            #expect(FileManager.default.fileExists(atPath: Self.iconSet.appendingPathComponent(filename).path),
                    "\(appearance) icon file \(filename) is missing")
        }
    }

    @Test(arguments: ["light", "dark", "tinted"])
    func everyIconIs1024Square(appearance: String) throws {
        let icon = try loadIcon(appearance)

        #expect(icon.width == 1024)
        #expect(icon.height == 1024)
    }

    @Test @MainActor func appBundleUsesTheAppIconSet() throws {
        let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])

        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }

    // MARK: - Light

    @Test func lightIconHasNoAlphaChannel() throws {
        let icon = try loadIcon("light")

        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(icon.image.alphaInfo),
                "The App Store rejects a main icon with an alpha channel")
        #expect(icon.pixel(x: 0, y: 0).a == 255)
        #expect(icon.pixel(x: 1023, y: 1023).a == 255)
    }

    // MARK: - Dark

    @Test func darkIconHasATransparentBackground() throws {
        let icon = try loadIcon("dark")

        for (x, y) in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (100, 512)] {
            #expect(icon.pixel(x: x, y: y).a == 0, "Background at (\(x), \(y)) should be transparent")
        }
    }

    @Test func darkIconArtworkIsBrightEnoughForADarkBackdrop() throws {
        let icon = try loadIcon("dark")

        // Fork and knife: everything opaque outside the badge.
        let artwork = icon.pixels { x, y, pixel in pixel.a > 200 && !isInsideBadge(x, y, radius: badgeInnerRadius + 30) }
        #expect(artwork.count > 10_000, "Fork and knife should be drawn")
        let averageLuminance = artwork.map(\.luminance).reduce(0, +) / Double(artwork.count)
        #expect(averageLuminance > 0.5, "Artwork luminance \(averageLuminance) is too dark for a dark backdrop")
    }

    @Test func darkIconDiffersFromLightIcon() throws {
        let light = try loadIcon("light")
        let dark = try loadIcon("dark")

        #expect(light.pixel(x: 0, y: 0) != dark.pixel(x: 0, y: 0))
    }

    // MARK: - Tinted

    @Test func tintedIconHasATransparentBackground() throws {
        let icon = try loadIcon("tinted")

        for (x, y) in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (100, 512)] {
            #expect(icon.pixel(x: x, y: y).a == 0, "Background at (\(x), \(y)) should be transparent")
        }
    }

    @Test func tintedIconIsGrayscaleSoTheSystemCanTintIt() throws {
        let icon = try loadIcon("tinted")

        let coloured = icon.pixels { _, _, pixel in
            pixel.a > 0 && (abs(Int(pixel.r) - Int(pixel.g)) > 2 || abs(Int(pixel.g) - Int(pixel.b)) > 2)
        }
        #expect(coloured.isEmpty, "\(coloured.count) coloured pixels found in the tinted icon")
    }

    @Test func tintedIconLeafIsCutOutOfTheBadge() throws {
        let icon = try loadIcon("tinted")

        let badge = icon.pixels { x, y, _ in isInsideBadge(x, y, radius: badgeInnerRadius) }
        let transparent = badge.filter { $0.a == 0 }.count
        let opaque = badge.filter { $0.a == 255 }.count

        // The badge is solid with a leaf-shaped hole, so the leaf stays visible under any tint.
        #expect(opaque > badge.count / 2, "Badge should be mostly solid")
        #expect(transparent > 2_000, "Leaf should be punched out of the badge (found \(transparent) clear pixels)")
    }

    @Test func darkIconLeafIsDrawnNotCutOut() throws {
        let icon = try loadIcon("dark")

        let badge = icon.pixels { x, y, _ in isInsideBadge(x, y, radius: badgeInnerRadius) }

        #expect(badge.allSatisfy { $0.a > 0 }, "In the dark icon the leaf sits on a solid badge")
    }

    // MARK: - Helpers

    private func isInsideBadge(_ x: Int, _ y: Int, radius: Double) -> Bool {
        let dx = Double(x - badgeCenter.x), dy = Double(y - badgeCenter.y)
        return dx * dx + dy * dy < radius * radius
    }

    /// Appearance ("light", "dark", "tinted") → filename, from Contents.json.
    private func iconEntries() throws -> [String: String] {
        let data = try Data(contentsOf: Self.iconSet.appendingPathComponent("Contents.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try #require(json["images"] as? [[String: Any]])
        var entries: [String: String] = [:]
        for image in images {
            let appearance = (image["appearances"] as? [[String: String]])?.first?["value"] ?? "light"
            entries[appearance] = image["filename"] as? String
        }
        return entries
    }

    private func loadIcon(_ appearance: String) throws -> IconBitmap {
        let filename = try #require(try iconEntries()[appearance], "No \(appearance) icon in Contents.json")
        let url = Self.iconSet.appendingPathComponent(filename)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "Can't read \(filename)")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil), "Can't decode \(filename)")
        return IconBitmap(image)
    }
}

/// An icon decoded into RGBA bytes for pixel checks.
struct IconBitmap {
    struct Pixel: Equatable {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8

        /// Relative luminance of the un-premultiplied colour, 0…1.
        var luminance: Double {
            guard a > 0 else { return 0 }
            let scale = 255 / Double(a)
            return (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) * scale / 255
        }
    }

    let image: CGImage
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        self.image = image
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.bytes = bytes
    }

    /// Pixel at (x, y), measured from the top left.
    func pixel(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }

    /// Every pixel matching `include` (x and y from the top left).
    func pixels(where include: (Int, Int, Pixel) -> Bool) -> [Pixel] {
        var result: [Pixel] = []
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x: x, y: y)
                if include(x, y, p) { result.append(p) }
            }
        }
        return result
    }
}
