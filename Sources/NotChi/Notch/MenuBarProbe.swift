import AppKit
import ApplicationServices

/// Measures how much of the menu bar beside the notch is actually free, so the collapsed
/// wings never cover app menus or status icons.
///
/// macOS 26+ draws every status item inside one MenuBarAgent window, so window bounds are
/// useless here; the Accessibility tree (`AXMenuBar` / `AXExtrasMenuBar`) has the real
/// frames. Querying every app is slow (some answer late), so a full sweep runs rarely and
/// in between only apps already known to own status items are re-queried.
final class MenuBarProbe: @unchecked Sendable {
    struct Extents: Equatable {
        /// Right edge of the frontmost app's menus, or nil when unknown.
        var menusMaxX: CGFloat?
        /// Left edge of the leftmost menu or status item right of the notch, or nil when unknown.
        var statusItemsMinX: CGFloat?
    }

    private let queue = DispatchQueue(label: "notchi.menubar-probe", qos: .utility)
    private var pidsWithExtras: Set<pid_t> = []
    private var lastFullSweep = Date.distantPast
    private let fullSweepInterval: TimeInterval = 20
    /// Main-actor only.
    private var cachedPIDs: [pid_t]?

    /// Measures in the background and calls back on the main actor.
    /// `notchRect` is in AppKit global coordinates; `primaryMaxY` converts AX (top-left) y.
    @MainActor
    func measure(notchRect: CGRect, primaryMaxY: CGFloat, completion: @escaping @MainActor (Extents) -> Void) {
        guard AXIsProcessTrusted() else {
            Task { @MainActor in completion(Extents()) }
            return
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Background agents (MenuBarAgent, VPN helpers…) own status items too, so include every app.
        // Listing apps is surprisingly costly, so the list is cached until an app launches or quits.
        if cachedPIDs == nil { cachedPIDs = NSWorkspace.shared.runningApplications.map(\.processIdentifier) }
        let apps = cachedPIDs ?? []
        queue.async { [self] in
            let extents = sweep(notchRect: notchRect, primaryMaxY: primaryMaxY, frontPID: frontPID, allPIDs: apps)
            Task { @MainActor in completion(extents) }
        }
    }

    /// Forces the next measurement to re-query every app (e.g. after an app launches).
    @MainActor
    func invalidate() {
        cachedPIDs = nil
        queue.async { [self] in lastFullSweep = .distantPast }
    }

    // MARK: - Background work

    private func sweep(notchRect: CGRect, primaryMaxY: CGFloat, frontPID: pid_t?, allPIDs: [pid_t]) -> Extents {
        // AX frames use a top-left origin on the primary screen; the notch strip spans this y range.
        let stripTop = primaryMaxY - notchRect.maxY
        let inStrip: (CGRect) -> Bool = { r in
            r.width > 0 && r.minY >= stripTop - 2 && r.minY < stripTop + notchRect.height
        }

        var extents = Extents()
        var minX: CGFloat?
        if let frontPID {
            let menus = itemFrames(of: frontPID, attribute: kAXMenuBarAttribute).filter(inStrip)
            extents.menusMaxX = menus.filter { $0.minX < notchRect.minX }.map(\.maxX).max()
            // Menus that don't fit left of the notch are moved to its right (e.g. Xcode's Help).
            minX = menus.filter { $0.minX >= notchRect.maxX - 2 }.map(\.minX).min()
        }

        let full = Date().timeIntervalSince(lastFullSweep) > fullSweepInterval
        let candidates = full ? allPIDs : allPIDs.filter(pidsWithExtras.contains)
        if full {
            lastFullSweep = Date()
            pidsWithExtras.removeAll()
        }
        for pid in candidates {
            let frames = itemFrames(of: pid, attribute: "AXExtrasMenuBar").filter(inStrip)
            guard !frames.isEmpty else { continue }
            pidsWithExtras.insert(pid)
            for frame in frames where frame.minX >= notchRect.maxX - 2 {
                minX = min(minX ?? .infinity, frame.minX)
            }
        }
        extents.statusItemsMinX = minX
        return extents
    }

    private func itemFrames(of pid: pid_t, attribute: String) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var barValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &barValue) == .success,
              let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID() else { return [] }
        let bar = barValue as! AXUIElement
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return [] }
        return children.compactMap(frame(of:))
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
