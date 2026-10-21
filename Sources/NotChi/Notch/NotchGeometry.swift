import AppKit

/// Where the hardware notch is (or where a virtual one should go) on a screen.
struct NotchGeometry: Equatable {
    /// Size of the physical notch, or of the virtual pill on screens without one.
    var notchSize: CGSize
    var hasNotch: Bool
    /// Frame of the whole screen in global coordinates.
    var screenFrame: CGRect

    /// Preferred width of each collapsed wing; it shrinks when the menu bar needs the room.
    static let wingWidth: CGFloat = 78
    /// Below this a wing is hidden rather than squeezed.
    static let minWingWidth: CGFloat = 54
    static let expandedSize = CGSize(width: 720, height: 330)

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: topInset)
        } else {
            hasNotch = false
            // Match the menu bar height so the pill sits flush with the top edge.
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: max(menuBar, 24))
        }
    }

    /// Transparent room around the expanded shape so its drop shadow isn't clipped by the window.
    static let shadowMargin: CGFloat = 40

    /// The panel always occupies the expanded frame (plus shadow room); SwiftUI animates the
    /// visible shape inside it.
    var panelFrame: CGRect {
        let size = Self.expandedSize
        let m = Self.shadowMargin
        return CGRect(x: screenFrame.midX - size.width / 2 - m, y: screenFrame.maxY - size.height - m,
                      width: size.width + m * 2, height: size.height + m)
    }

    /// Global-coordinate rect of the hardware notch (or virtual pill).
    var notchRect: CGRect {
        CGRect(x: screenFrame.midX - notchSize.width / 2, y: screenFrame.maxY - notchSize.height,
               width: notchSize.width, height: notchSize.height)
    }

    /// Global-coordinate rect of the collapsed shape: the notch plus whatever wings are shown.
    func collapsedRect(leftWing: CGFloat, rightWing: CGFloat) -> CGRect {
        let notch = notchRect
        return CGRect(x: notch.minX - leftWing, y: notch.minY,
                      width: notch.width + leftWing + rightWing, height: notch.height)
    }

    /// Width a wing may take given the nearest menu bar content on that side.
    static func wingWidth(available: CGFloat?) -> CGFloat {
        guard let available else { return wingWidth }
        let fit = min(wingWidth, available - 8)
        return fit >= minWingWidth ? fit : 0
    }

    /// Global-coordinate rect of the visible expanded shape.
    var expandedRect: CGRect {
        let size = Self.expandedSize
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Prefer the built-in display (which carries the notch); fall back to the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
