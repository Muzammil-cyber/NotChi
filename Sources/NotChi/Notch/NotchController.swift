import AppKit
import SwiftUI

/// Owns the notch panel and decides when it expands or collapses.
///
/// Hover is detected by polling `NSEvent.mouseLocation` rather than with event
/// monitors: polling needs no permissions, keeps working during drags from other
/// apps, and costs next to nothing at 30 Hz.
@MainActor
final class NotchController {
    static private(set) var shared: NotchController!

    private let state = NotchState.shared
    private let settings = Settings.shared
    private let host: ModuleHost
    private let panel: NotchPanel

    private var pollTimer: Timer?
    private var hoverStart: Date?
    private var exitStart: Date?
    /// Opened by the hotkey: stay open until the pointer visits and leaves, Escape, or an outside click.
    private var stickyOpen = false
    private var pointerVisitedSinceSticky = false
    private var outsideClickMonitor: Any?
    private var hotKey: HotKey?
    private var settingsObservation: Any?

    private let expandDelay: TimeInterval = 0.12
    private let collapseDelay: TimeInterval = 0.35

    init(host: ModuleHost) {
        self.host = host
        panel = NotchPanel(contentRect: state.geometry.panelFrame)
        Self.shared = self

        let root = NotchRootView(state: state, settings: settings, host: host)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onEscape = { [weak self] in self?.collapse() }

        layout()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleOutsideClick() }
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        registerHotKey()
        observeHotKeySetting()
    }

    // MARK: - Public API

    func toggle() {
        if state.isExpanded {
            collapse()
        } else {
            expand(sticky: true)
            panel.makeKey()
        }
    }

    func expand(sticky: Bool = false) {
        stickyOpen = sticky
        pointerVisitedSinceSticky = false
        exitStart = nil
        guard !state.isExpanded else { return }
        if state.selectedModuleID.isEmpty { state.selectedModuleID = host.modules.first?.id ?? "" }
        panel.ignoresMouseEvents = false
        state.isExpanded = true
        host.visibilityChanged(expanded: true, selected: state.selectedModuleID)
    }

    /// Collapses the panel and hands keyboard focus back to the app the user was in.
    func collapse() {
        stickyOpen = false
        hoverStart = nil
        exitStart = nil
        state.holdOpenReasons.removeAll()
        guard state.isExpanded else { return }
        state.isExpanded = false
        panel.ignoresMouseEvents = true
        host.visibilityChanged(expanded: false, selected: state.selectedModuleID)
        if panel.isKeyWindow {
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    func select(moduleID: String) {
        guard moduleID != state.selectedModuleID else { return }
        state.selectedModuleID = moduleID
        host.visibilityChanged(expanded: state.isExpanded, selected: moduleID)
    }

    /// Lets a text field inside the panel receive typing.
    func focusPanel() {
        panel.makeKey()
    }

    // MARK: - Internals

    private func layout() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        if geometry != state.geometry { state.geometry = geometry }
        panel.setFrame(geometry.panelFrame, display: true)
    }

    private var wingsVisible: Bool { settings.showWings && host.hasWings }

    private func poll() {
        let mouse = NSEvent.mouseLocation
        let geometry = state.geometry
        let dragging = NSEvent.pressedMouseButtons & 1 != 0

        if !state.isExpanded {
            let trigger = geometry.collapsedRect(withWings: wingsVisible).insetBy(dx: -6, dy: -2)
            // Extend the trigger zone upward so slamming the cursor into the top edge counts.
            let zone = trigger.union(CGRect(x: trigger.minX, y: trigger.maxY, width: trigger.width, height: 4))
            guard zone.contains(mouse), settings.hoverToExpand || dragging else {
                hoverStart = nil
                return
            }
            // A drag (e.g. a file from Finder) expands immediately so the stash can receive it.
            if dragging {
                expand()
                return
            }
            if let start = hoverStart {
                if Date().timeIntervalSince(start) >= expandDelay { expand() }
            } else {
                hoverStart = Date()
            }
            return
        }

        let inside = visibleExpandedRect().insetBy(dx: -4, dy: -4).contains(mouse)
        if inside {
            pointerVisitedSinceSticky = true
            exitStart = nil
            return
        }
        if stickyOpen && !pointerVisitedSinceSticky { return }
        if !state.holdOpenReasons.isEmpty || dragging { return }
        if let start = exitStart {
            if Date().timeIntervalSince(start) >= collapseDelay { collapse() }
        } else {
            exitStart = Date()
        }
    }

    private func visibleExpandedRect() -> CGRect {
        let frame = state.geometry.panelFrame
        let size = NotchGeometry.expandedSize
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func handleOutsideClick() {
        guard state.isExpanded else { return }
        // Global monitors only fire for clicks outside our own windows.
        if !visibleExpandedRect().contains(NSEvent.mouseLocation) { collapse() }
    }

    private func registerHotKey() {
        hotKey?.unregister()
        hotKey = nil
        guard let combo = settings.hotKey.carbon else { return }
        hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers) { [weak self] in
            self?.toggle()
        }
    }

    private func observeHotKeySetting() {
        withObservationTracking {
            _ = settings.hotKey
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.registerHotKey()
                self?.observeHotKeySetting()
            }
        }
    }
}
