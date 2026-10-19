//
//  ExternalLinksTests.swift
//  SmartMealPlannerTests
//
//  YouTube links open in the YouTube app when it's installed, AH's Bonus page in the AH app; otherwise Safari.
//

import Foundation
import Testing
import UIKit
@testable import SmartMealPlanner

/// Records what would be opened; `appInstalled` decides whether a universal-link-only open succeeds.
@MainActor
final class FakeURLOpener: URLOpening {
    var appInstalled: Bool
    private(set) var opened: [(url: URL, universalLinksOnly: Bool)] = []

    init(appInstalled: Bool) {
        self.appInstalled = appInstalled
    }

    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any],
              completionHandler: (@MainActor @Sendable (Bool) -> Void)?) {
        let appOnly = options[.universalLinksOnly] as? Bool == true
        opened.append((url, appOnly))
        completionHandler?(appOnly ? appInstalled : true)
    }
}

@MainActor
@Suite("External links")
struct ExternalLinksTests {

    private let video = URL(string: "https://www.youtube.com/watch?v=J6N_lEmp4mY")!

    @Test func youTubeLinkOpensInTheAppWhenItIsInstalled() {
        let opener = FakeURLOpener(appInstalled: true)
        ExternalLinks.open(video, application: opener)

        #expect(opener.opened.count == 1)
        #expect(opener.opened[0].url == video && opener.opened[0].universalLinksOnly, "handed to the YouTube app only")
    }

    @Test func youTubeLinkFallsBackToSafariWithoutTheApp() {
        let opener = FakeURLOpener(appInstalled: false)
        ExternalLinks.open(video, application: opener)

        #expect(opener.opened.map(\.universalLinksOnly) == [true, false], "tried the app, then opened normally")
        #expect(opener.opened.last?.url == video)
    }

    @Test func otherLinksOpenNormally() {
        let opener = FakeURLOpener(appInstalled: true)
        let cookbook = URL(string: "https://www.amazon.com/s?k=the+wok")!
        ExternalLinks.open(cookbook, application: opener)

        #expect(opener.opened.count == 1)
        #expect(!opener.opened[0].universalLinksOnly)
    }

    @Test(arguments: ["https://www.youtube.com/watch?v=abc", "https://m.youtube.com/watch?v=abc",
                      "https://youtu.be/abc", "https://youtube.com/shorts/abc"])
    func youTubeHostsAreRecognised(link: String) {
        #expect(YouTubeLink.isYouTube(URL(string: link)!))
    }

    @Test func shortLinksBecomeWatchLinksForTheApp() {
        let short = URL(string: "https://youtu.be/J6N_lEmp4mY?t=42")!
        #expect(YouTubeLink.appLink(for: short).absoluteString == "https://www.youtube.com/watch?v=J6N_lEmp4mY&t=42")
        #expect(YouTubeLink.appLink(for: video) == video, "watch links are already right")
        #expect(!YouTubeLink.isYouTube(URL(string: "https://vimeo.com/123")!))
    }

    @Test func albertHeijnBonusOpensInTheAHAppElseSafari() {
        let withApp = FakeURLOpener(appInstalled: true)
        ExternalLinks.open(AlbertHeijn.bonusURL, application: withApp)
        #expect(withApp.opened.map(\.universalLinksOnly) == [true])

        let withoutApp = FakeURLOpener(appInstalled: false)
        ExternalLinks.open(AlbertHeijn.bonusURL, application: withoutApp)
        #expect(withoutApp.opened.map(\.universalLinksOnly) == [true, false])
        #expect(withoutApp.opened.last?.url == AlbertHeijn.bonusURL)
    }

    @Test func onlyAHHostsCountAsAlbertHeijn() {
        #expect(ExternalLinks.isAlbertHeijn(URL(string: "https://www.ah.nl/bonus")!))
        #expect(ExternalLinks.isAlbertHeijn(URL(string: "https://ah.nl")!))
        #expect(!ExternalLinks.isAlbertHeijn(URL(string: "https://blah.nl/bonus")!))
    }
}
