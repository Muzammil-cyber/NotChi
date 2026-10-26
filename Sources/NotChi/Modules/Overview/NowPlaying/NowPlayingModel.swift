// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import ImageIO
import Observation

/// What's playing system-wide (Music, Spotify, a browser tab…) and controls for it.
/// Fed by `MediaRemoteBridge`; only runs while Now Playing is turned on in Settings.
@MainActor
@Observable
final class NowPlayingModel {
    private(set) var title: String?
    private(set) var artist: String?
    private(set) var album: String?
    private(set) var bundleID: String?
    private(set) var isPlaying = false
    private(set) var duration: Double?
    private(set) var artwork: NSImage?
    /// Elapsed seconds as of `elapsedAt`; the current position is extrapolated from these
    /// so nothing has to update every second.
    private(set) var elapsed: Double = 0
    private(set) var elapsedAt = Date()
    private(set) var rate: Double = 1

    var hasMedia: Bool { title != nil }

    @ObservationIgnored private let bridge = MediaRemoteBridge()
    @ObservationIgnored private var payload: [String: Any] = [:]
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var running = false

    init() {
        bridge.onUpdate = { [weak self] payload, diff in self?.apply(payload, diff: diff) }
    }

    func position(at date: Date) -> Double {
        var position = elapsed
        if isPlaying { position += date.timeIntervalSince(elapsedAt) * rate }
        if let duration { position = min(position, duration) }
        return max(0, position)
    }

    // MARK: Lifecycle

    func setRunning(_ run: Bool) {
        guard run != running else { return }
        running = run
        if run {
            bridge.start()
        } else {
            bridge.stop()
            clear()
        }
    }

    // MARK: Controls

    func togglePlayPause() {
        // Optimistic, so the button flips at once; the next update confirms it.
        elapsed = position(at: Date())
        elapsedAt = Date()
        isPlaying.toggle()
        bridge.send(.togglePlayPause)
    }

    func next() { bridge.send(.nextTrack) }
    func previous() { bridge.send(.previousTrack) }

    func seek(to seconds: Double) {
        elapsed = seconds
        elapsedAt = Date()
        bridge.seek(to: seconds)
    }

    func openSourceApp() {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Updates

    private func apply(_ update: [String: Any], diff: Bool) {
        guard running else { return }
        if diff {
            for (key, value) in update {
                if value is NSNull { payload.removeValue(forKey: key) } else { payload[key] = value }
            }
        } else {
            payload = update
        }

        let newTitle = payload["title"] as? String
        if title != newTitle { title = newTitle }
        let newArtist = payload["artist"] as? String
        if artist != newArtist { artist = newArtist }
        let newAlbum = payload["album"] as? String
        if album != newAlbum { album = newAlbum }
        let newBundle = (payload["parentApplicationBundleIdentifier"] ?? payload["bundleIdentifier"]) as? String
        if bundleID != newBundle { bundleID = newBundle }
        let playing = payload["playing"] as? Bool ?? false
        if isPlaying != playing { isPlaying = playing }
        let newDuration = (payload["durationMicros"] as? NSNumber).map { $0.doubleValue / 1e6 }
        if duration != newDuration { duration = newDuration }
        rate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        if rate <= 0 { rate = 1 }
        if let micros = (payload["elapsedTimeMicros"] as? NSNumber)?.doubleValue {
            elapsed = micros / 1e6
            if let stamp = (payload["timestampEpochMicros"] as? NSNumber)?.doubleValue {
                elapsedAt = Date(timeIntervalSince1970: stamp / 1e6)
            } else {
                elapsedAt = Date()
            }
        }
        updateArtwork()
    }

    /// Decodes artwork once per image, off the main thread, as a small thumbnail: players
    /// send full-size covers, which would otherwise sit in memory at several MB each.
    private func updateArtwork() {
        guard let base64 = payload["artworkData"] as? String else {
            if artworkKey != nil { artworkKey = nil; artwork = nil }
            return
        }
        let key = "\(base64.count):\(base64.prefix(64)):\(base64.suffix(64))"
        guard key != artworkKey else { return }
        artworkKey = key
        Task.detached(priority: .utility) {
            let image = Self.thumbnail(base64: base64, maxPixels: 240)
            await MainActor.run { [weak self] in
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
            }
        }
    }

    nonisolated private static func thumbnail(base64: String, maxPixels: Int) -> NSImage? {
        guard let data = Data(base64Encoded: base64),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
    }

    private func clear() {
        payload = [:]
        artworkKey = nil
        title = nil; artist = nil; album = nil; bundleID = nil
        isPlaying = false; duration = nil; artwork = nil
    }
}
