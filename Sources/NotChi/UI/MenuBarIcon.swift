// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit

/// The NotChi "NC" monogram for the menu bar. The app icon's circuit-board artwork turns to
/// noise at 18 pt, so this redraws its letterforms (a blocky N, a C with cut corners) as a
/// one-color template image that follows the menu bar's light and dark appearance.
enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let weight: CGFloat = 2.4
            let bottom: CGFloat = 2.5, top: CGFloat = 15.5

            // N: one stroked line; the sharp turns bevel into the logo's clipped corners.
            let n = NSBezierPath()
            n.move(to: NSPoint(x: 1.7, y: bottom))
            n.line(to: NSPoint(x: 1.7, y: top))
            n.line(to: NSPoint(x: 6.8, y: bottom))
            n.line(to: NSPoint(x: 6.8, y: top))
            n.lineWidth = weight
            n.lineJoinStyle = .miter
            n.miterLimit = 1.5
            n.lineCapStyle = .butt
            n.stroke()

            // C: an octagonal outline open on the right.
            let left: CGFloat = 11, right: CGFloat = 16.3
            let high = top - weight / 2, low = bottom + weight / 2
            let cut: CGFloat = 2.2, tip: CGFloat = 1.6
            let c = NSBezierPath()
            c.move(to: NSPoint(x: right, y: high - tip))
            c.line(to: NSPoint(x: right - tip, y: high))
            c.line(to: NSPoint(x: left + cut, y: high))
            c.line(to: NSPoint(x: left, y: high - cut))
            c.line(to: NSPoint(x: left, y: low + cut))
            c.line(to: NSPoint(x: left + cut, y: low))
            c.line(to: NSPoint(x: right - tip, y: low))
            c.line(to: NSPoint(x: right, y: low + tip))
            c.lineWidth = weight
            c.lineJoinStyle = .miter
            c.lineCapStyle = .butt
            c.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NotChi"
        return image
    }
}
