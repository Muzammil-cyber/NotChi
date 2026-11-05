// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

// MARK: - Expanded view

struct NowPlayingExpandedView: View {
    let model: NowPlayingModel

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        Group {
            if model.hasMedia {
                // Half of the Overview tab, beside the calendar.
                HStack(spacing: 12) {
                    artwork
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        Spacer(minLength: 8)
                        ScrubBar(model: model)
                        controls
                            .padding(.top, 6)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.top, 12)
                }
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .frame(maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .enableInjection()
    }

    /// Cover art with a soft shadow. It shrinks a little while paused, like Apple Music, so the
    /// state reads at a glance. The source app's icon sits on the corner as a badge.
    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkView(image: model.artwork, size: .infinity, radius: 14)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .scaleEffect(model.isPlaying ? 1 : 0.93)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.isPlaying)
            if let icon = sourceIcon {
                Button { model.openSourceApp() } label: {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .help("Open the app that's playing")
                .padding([.bottom, .trailing], 8)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.title ?? "")
                .font(.system(size: 18, weight: .bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let artist = model.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            if let album = model.album, !album.isEmpty {
                Text(album)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            ControlButton(symbol: "backward.fill", size: 16, help: "Previous") { model.previous() }
            // The main action gets a filled disc so it stands apart from skip.
            ControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 20,
                          help: model.isPlaying ? "Pause" : "Play", filled: true) { model.togglePlayPause() }
            ControlButton(symbol: "forward.fill", size: 16, help: "Next") { model.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceIcon: NSImage? {
        guard let id = model.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            if !MediaRemoteBridge.isAvailable {
                Text("The media helper is missing from this build. Run scripts/build-mediaremote-adapter.sh.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

/// A transport button: a soft highlight on hover and a small press squeeze. `filled` draws the
/// white disc used for play/pause.
struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let help: String
    var filled = false
    let action: () -> Void

    @State private var hovering = false

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Color.white)
                .frame(width: filled ? 44 : 36, height: filled ? 44 : 36)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(SqueezeStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
        .enableInjection()
    }

    private var fill: Color {
        if filled { return .white.opacity(hovering ? 1 : 0.92) }
        return .white.opacity(hovering ? 0.14 : 0)
    }
}

struct SqueezeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Elapsed and remaining time over a draggable bar. Ticks once a second, and only while
/// playing and on screen.
private struct ScrubBar: View {
    let model: NowPlayingModel
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        if model.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { context in bar(at: context.date) }
        } else {
            bar(at: Date())
        }
    }

    private func bar(at date: Date) -> some View {
        let duration = model.duration ?? 0
        let position = model.position(at: date)
        let fraction = dragFraction ?? (duration > 0 ? position / duration : 0)
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                }
                .frame(height: dragFraction != nil ? 14 : hovering ? 11 : 8)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragFraction != nil)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .gesture(duration > 0 ? DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(1, max(0, $0.location.x / geo.size.width)) }
                    .onEnded { _ in
                        if let dragFraction { model.seek(to: dragFraction * duration) }
                        dragFraction = nil
                    } : nil)
            }
            .frame(height: 18)
            HStack {
                Text(Self.time(dragFraction.map { $0 * duration } ?? position))
                Spacer()
                Text(duration > 0 ? "-" + Self.time(max(0, duration - (dragFraction.map { $0 * duration } ?? position))) : "")
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Rounded cover art, or a note placeholder. Also used by the wings.
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    #if DEBUG
    @ObserveInjection var forceRedraw
    #endif

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .enableInjection()
    }
}
