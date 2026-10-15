// Renders the SmartMealPlanner app icon (light, dark, tinted) as 1024×1024 PNGs.
//
// Usage (from the repo root):
//   swiftc -o /tmp/make_icon docs/app-icon/make_icon.swift
//   /tmp/make_icon SmartMealPlanner/Assets.xcassets/AppIcon.appiconset
import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

enum Variant { case light, dark, tinted }

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func drawCentered(_ image: NSImage, at center: CGPoint, operation: NSCompositingOperation = .sourceOver) {
    let s = image.size
    image.draw(in: CGRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height),
               from: .zero, operation: operation, fraction: 1)
}

func render(_ variant: Variant, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)

    // Background: brand green gradient (light). Dark and tinted use a transparent background
    // so iOS can draw its own dark / tinted backdrop.
    let foreground: NSColor
    let badgeFill: NSColor
    let leafColor: NSColor
    switch variant {
    case .light:
        NSGradient(starting: rgb(0x3A9169), ending: rgb(0x1F5A41))!.draw(in: canvas, angle: -60)
        foreground = .white
        badgeFill = rgb(0xE3F1EA)
        leafColor = rgb(0x2E7D5B)
    case .dark:
        foreground = rgb(0x8FD3B0)
        badgeFill = rgb(0x2E7D5B)
        leafColor = rgb(0xE3F1EA)
    case .tinted:
        foreground = .white
        badgeFill = .white
        leafColor = .black   // punched out below, so the tint can't flatten it
    }

    // Fork and knife, slightly left of centre and low to leave room for the badge.
    drawCentered(symbol("fork.knife", pointSize: 430, weight: .semibold, color: foreground),
                 at: CGPoint(x: 492, y: 482))

    // Leaf badge, top right, separated from the knife by a ring of background.
    let badgeCenter = CGPoint(x: 712, y: 712)
    let badgeRadius: CGFloat = 132
    let ringRadius = badgeRadius + 26
    let ring = NSBezierPath(ovalIn: CGRect(x: badgeCenter.x - ringRadius, y: badgeCenter.y - ringRadius,
                                           width: ringRadius * 2, height: ringRadius * 2))
    NSGraphicsContext.saveGraphicsState()
    ring.addClip()
    if variant == .light {
        NSGradient(starting: rgb(0x3A9169), ending: rgb(0x1F5A41))!.draw(in: canvas, angle: -60)
    } else {
        NSGraphicsContext.current?.compositingOperation = .clear
        canvas.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    badgeFill.setFill()
    NSBezierPath(ovalIn: CGRect(x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
                                width: badgeRadius * 2, height: badgeRadius * 2)).fill()
    drawCentered(symbol("leaf.fill", pointSize: 132, weight: .semibold, color: leafColor), at: badgeCenter,
                 operation: variant == .tinted ? .destinationOut : .sourceOver)

    NSGraphicsContext.restoreGraphicsState()

    // The App Store rejects a main icon with an alpha channel, so flatten the opaque light icon
    // to RGB. (AppKit can't draw into an alpha-less bitmap directly; Core Graphics can.)
    let image = variant == .light ? flattened(rep.cgImage!) : rep.cgImage!
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(path)")
}

func flattened(_ image: CGImage) -> CGImage {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()!
}

let out = CommandLine.arguments[1]
render(.light, to: "\(out)/AppIcon.png")
render(.dark, to: "\(out)/AppIcon-Dark.png")
render(.tinted, to: "\(out)/AppIcon-Tinted.png")
print("rendered")
