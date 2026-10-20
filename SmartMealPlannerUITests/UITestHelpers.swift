//
//  UITestHelpers.swift
//  SmartMealPlannerUITests
//
//  Shared helpers for launching the app in a known state and finding elements.
//

import XCTest

enum LaunchFlag {
    // Must match `LaunchArguments` in the app.
    static let resetState = "-uiTestingResetState"
    static let skipSplash = "-uiTestingSkipSplash"
    static let splashSeconds = "-uiTestingSplashSeconds"
    static let bundledData = "-uiTestingBundledData"
    static let fixtureRecipes = "-uiTestingFixtureRecipes"
    static let postcodeLookupSeconds = "-uiTestingPostcodeLookupSeconds"
}

extension XCUIApplication {

    /// Launches the app. By default it starts from a clean slate (no saved preferences, routine,
    /// plan or settings), skips the splash screen and uses the bundled sample offers instead of the live feed.
    @discardableResult
    static func launchForTesting(resetState: Bool = true, skipSplash: Bool = true, liveData: Bool = false,
                                 extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (resetState ? [LaunchFlag.resetState] : []) + (skipSplash ? [LaunchFlag.skipSplash] : [])
            + (liveData ? [] : [LaunchFlag.bundledData]) + extraArguments
        app.launch()
        return app
    }

    /// Switches to a tab by its title ("Plan", "Offers", "Preferences", "Settings").
    func openTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = tabBars.buttons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab \(title) not found", file: file, line: line)
        tab.tap()
    }

    /// Any element whose label contains `text` (useful for cards that combine several texts).
    func element(containing text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A button whose label contains `text` (selected chips add a checkmark to their label).
    func button(containing text: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Element with an accessibility identifier, whatever its type.
    func element(withID identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }

    /// Whether `element` is on screen and not hidden behind the floating tab bar (XCTest still calls an element
    /// under the tab bar hittable, but a tap there lands on the tab bar).
    func canTap(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let tabBar = tabBars.firstMatch
        guard tabBar.exists else { return true }
        return element.frame.maxY <= tabBar.frame.minY
    }

    /// Swipes up until `element` can be tapped.
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !canTap(element) && swipes < maxSwipes {
            swipeUp()
            swipes += 1
        }
        XCTAssertTrue(canTap(element), "Could not scroll to \(element)", file: file, line: line)
    }

    /// Scrolls whichever way is needed: down first, then back up if the element wasn't below.
    func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !canTap(element) && swipes < 6 {
            swipeUp()
            swipes += 1
        }
        if !canTap(element) {
            scrollUpTo(element, maxSwipes: 12, file: file, line: line)
        }
    }

    /// Swipes down (towards the top of the screen) until `element` can be tapped.
    func scrollUpTo(_ element: XCUIElement, maxSwipes: Int = 8, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !canTap(element) && swipes < maxSwipes {
            swipeDown()
            swipes += 1
        }
        XCTAssertTrue(canTap(element), "Could not scroll up to \(element)", file: file, line: line)
    }

    /// Relative luminance (0 = black, 1 = white) of the screen at a point, in points from the top left.
    /// Used to check that the light / dark theme actually rendered.
    func screenLuminance(at point: CGPoint) -> CGFloat {
        let image = XCUIScreen.main.screenshot().image
        guard let cgImage = image.cgImage else { return -1 }
        let scale = CGFloat(cgImage.width) / image.size.width
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw the image shifted so the requested pixel lands on the 1×1 context.
        let x = point.x * scale, y = point.y * scale
        context.draw(cgImage, in: CGRect(x: -x, y: -(CGFloat(cgImage.height) - y - 1),
                                         width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        let (r, g, b) = (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
