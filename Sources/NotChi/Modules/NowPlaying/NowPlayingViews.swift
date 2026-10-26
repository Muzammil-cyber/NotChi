// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

// MARK: - Expanded view

struct NowPlayingExpandedView: View {
    let model: NowPlayingModel

    var body: some View {
        Group {
            if model.hasMedia {
                // Half of the Overview tab, beside the calendar.
                HStack(spacing: 14) {
                    ArtworkView(image: model.artwork, size: 88, radius: 10)
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        ScrubBar(model: model)
                        controls
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title ?? "")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text([model.artist, model.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let icon = sourceIcon {
                Button { model.openSourceApp() } label: {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Open the app that's playing")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            control("backward.fill", size: 15, help: "Previous") { model.previous() }
            control(model.isPlaying ? "pause.fill" : "play.fill", size: 22,
                    help: model.isPlaying ? "Pause" : "Play") { model.togglePlayPause() }
            control("forward.fill", size: 15, help: "Next") { model.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private func control(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
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

/// Elapsed and remaining time over a draggable bar. Ticks once a second, and only while
/// playing and on screen.
private struct ScrubBar: View {
    let model: NowPlayingModel
    @State private var dragFraction: Double?

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
        return VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                }
                .frame(height: dragFraction == nil ? 4 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(duration > 0 ? DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(1, max(0, $0.location.x / geo.size.width)) }
                    .onEnded { _ in
                        if let dragFraction { model.seek(to: dragFraction * duration) }
                        dragFraction = nil
                    } : nil)
            }
            .frame(height: 10)
            HStack {
                Text(Self.time(dragFraction.map { $0 * duration } ?? position))
                Spacer()
                Text(duration > 0 ? "-" + Self.time(max(0, duration - (dragFraction.map { $0 * duration } ?? position))) : "")
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

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
    }
}

// MARK: - Wings

struct NowPlayingLeftWing: View {
    let model: NowPlayingModel

    var body: some View {
        ArtworkView(image: model.artwork, size: 20, radius: 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NowPlayingRightWing: View {
    let model: NowPlayingModel

    var body: some View {
        EqualizerBars(animating: model.isPlaying)
            .frame(width: 18, height: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bouncing bars drawn with Core Animation: the render server runs the loop, so a
/// collapsed notch with music playing costs the app no per-frame work.
private struct EqualizerBars: NSViewRepresentable {
    let animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.setAnimating(animating && !reduceMotion)
    }
}

final class EqualizerView: NSView {
    private let bars = (0..<4).map { _ in CALayer() }
    private let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.5]
    private var animating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = 1
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let gap: CGFloat = 2
        let width = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: 0)
            if !animating { bar.transform = CATransform3DMakeScale(1, 0.3, 1) }
        }
        CATransaction.commit()
    }

    func setAnimating(_ animate: Bool) {
        guard animate != animating else { return }
        animating = animate
        for (i, bar) in bars.enumerated() {
            if animate {
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = 0.2
                bounce.toValue = 1
                bounce.duration = durations[i]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bounce.timeOffset = Double(i) * 0.13
                bar.add(bounce, forKey: "bounce")
            } else {
                bar.removeAnimation(forKey: "bounce")
                bar.transform = CATransform3DMakeScale(1, 0.3, 1)
            }
        }
    }
}
