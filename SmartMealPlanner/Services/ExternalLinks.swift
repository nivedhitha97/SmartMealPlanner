//
//  ExternalLinks.swift
//  SmartMealPlanner
//
//  Opening links outside the app: YouTube videos go to the YouTube app when it's installed, else to Safari.
//

import Foundation
import UIKit

enum YouTubeLink {

    private static let hosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
                                             "youtu.be", "www.youtu.be"]

    static func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    /// The canonical https link the YouTube app claims as a universal link ("youtu.be/ID" → "youtube.com/watch?v=ID").
    static func appLink(for url: URL) -> URL {
        guard let host = url.host?.lowercased(), host.hasSuffix("youtu.be") else { return url }
        let id = url.pathComponents.dropFirst().first ?? ""
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: id)]
            + (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        return components.url ?? url
    }
}

@MainActor
enum ExternalLinks {

    /// Opens a URL: a YouTube link opens in the YouTube app if it's installed (iOS hands the link to the app that
    /// claims it, with no Info.plist query schemes needed) and otherwise in Safari; any other link opens normally.
    static func open(_ url: URL, application: URLOpening = UIApplication.shared) {
        guard YouTubeLink.isYouTube(url) else {
            application.open(url, options: [:], completionHandler: nil)
            return
        }
        let appLink = YouTubeLink.appLink(for: url)
        application.open(appLink, options: [.universalLinksOnly: true]) { openedInApp in
            if !openedInApp {
                application.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}

/// UIApplication's URL opening, so tests can check what is opened.
@MainActor
protocol URLOpening {
    func open(_ url: URL, options: [UIApplication.OpenExternalURLOptionsKey: Any],
              completionHandler: (@MainActor @Sendable (Bool) -> Void)?)
}

extension UIApplication: URLOpening {}
