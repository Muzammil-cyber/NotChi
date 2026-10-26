// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

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
