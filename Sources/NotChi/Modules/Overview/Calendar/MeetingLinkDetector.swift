// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import EventKit

/// A video call link found in a calendar event.
struct MeetingLink: Equatable {
    enum Service: String {
        case zoom = "Zoom", meet = "Google Meet", teams = "Teams", webex = "Webex"
    }

    let url: URL
    let service: Service

    /// Opens Zoom links straight in the Zoom app when it's installed; everything else
    /// goes to the default handler (browser or the service's app).
    func open() {
        NSWorkspace.shared.open(Self.zoomAppURL(for: self) ?? url)
    }

    private static func zoomAppURL(for link: MeetingLink) -> URL? {
        guard link.service == .zoom, link.url.scheme == "https",
              NSWorkspace.shared.urlForApplication(withBundleIdentifier: "us.zoom.xos") != nil,
              let components = URLComponents(url: link.url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "j" else { return nil }
        var app = URLComponents()
        app.scheme = "zoommtg"
        app.host = components.host
        app.path = "/join"
        var query: [URLQueryItem] = [URLQueryItem(name: "confno", value: String(parts[1]))]
        if let password = components.queryItems?.first(where: { $0.name == "pwd" }) { query.append(password) }
        app.queryItems = query
        return app.url
    }
}

enum MeetingLinkDetector {
    private static let sources: [(MeetingLink.Service, String)] = [
        (.zoom, #"(?:https://[\w.-]*zoom\.us/(?:j|my|w)/|zoommtg://)[^\s<>"']+"#),
        (.meet, #"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\s<>"']*"#),
        (.teams, #"https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>"']+"#),
        (.webex, #"https://[\w.-]*webex\.com/[^\s<>"']+"#),
    ]
    private static let patterns = sources.map { ($0.0, try! NSRegularExpression(pattern: $0.1, options: .caseInsensitive)) }

    /// Looks in the event's URL, location and notes, in that order.
    static func link(in event: EKEvent) -> MeetingLink? {
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in texts {
            if let link = link(in: text) { return link }
        }
        return nil
    }

    static func link(in text: String) -> MeetingLink? {
        let range = NSRange(text.startIndex..., in: text)
        for (service, regex) in patterns {
            guard let match = regex.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { continue }
            // Notes are often HTML or prose: undo entity escaping, drop trailing punctuation.
            var raw = String(text[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
            while let last = raw.last, ").,;>]".contains(last) { raw.removeLast() }
            if let url = URL(string: raw) { return MeetingLink(url: url, service: service) }
        }
        return nil
    }
}
