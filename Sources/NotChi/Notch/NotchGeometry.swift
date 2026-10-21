import AppKit

/// Where the hardware notch is (or where a virtual one should go) on a screen.
struct NotchGeometry: Equatable {
    /// Size of the physical notch, or of the virtual pill on screens without one.
    var notchSize: CGSize
    var hasNotch: Bool
    /// Frame of the whole screen in global coordinates.
    var screenFrame: CGRect

    static let wingWidth: CGFloat = 78
    static let expandedSize = CGSize(width: 680, height: 330)

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

    /// The panel always occupies the expanded frame; SwiftUI animates the visible shape inside it.
    var panelFrame: CGRect {
        let size = Self.expandedSize
        return CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Global-coordinate rect of the collapsed shape (notch plus optional wings).
    func collapsedRect(withWings: Bool) -> CGRect {
        let width = notchSize.width + (withWings ? Self.wingWidth * 2 : 0)
        return CGRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - notchSize.height,
                      width: width, height: notchSize.height)
    }

    var expandedRect: CGRect { panelFrame }

    /// Prefer the built-in display (which carries the notch); fall back to the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
