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
    private let menuBarProbe = MenuBarProbe()
    private var probeTimer: Timer?

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
        startMenuBarProbe()
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

    private func poll() {
        let mouse = NSEvent.mouseLocation
        let geometry = state.geometry
        let dragging = NSEvent.pressedMouseButtons & 1 != 0

        if !state.isExpanded {
            let trigger = geometry.collapsedRect(leftWing: state.leftWingWidth, rightWing: state.rightWingWidth)
                .insetBy(dx: -6, dy: -2)
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

    private func visibleExpandedRect() -> CGRect { state.geometry.expandedRect }

    private func handleOutsideClick() {
        guard state.isExpanded else { return }
        // Global monitors only fire for clicks outside our own windows.
        if !visibleExpandedRect().contains(NSEvent.mouseLocation) { collapse() }
    }

    // MARK: - Wings vs. menu bar

    /// Re-measures the menu bar every couple of seconds while collapsed, and right away
    /// when the frontmost app (and so its menus) changes.
    private func startMenuBarProbe() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWings() }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.menuBarProbe.invalidate()
                    self?.updateWings()
                }
            }
        }
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWings() }
        }
        RunLoop.main.add(timer, forMode: .common)
        probeTimer = timer
        observeWingSetting()
        updateWings()
    }

    private func updateWings() {
        guard settings.showWings, host.hasWings else {
            setWings(left: 0, right: 0)
            return
        }
        guard !state.isExpanded else { return }
        let notch = state.geometry.notchRect
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? state.geometry.screenFrame.maxY
        menuBarProbe.measure(notchRect: notch, primaryMaxY: primaryMaxY) { [weak self] extents in
            guard let self, settings.showWings else { return }
            let left = host.leftWing == nil ? 0
                : NotchGeometry.wingWidth(available: extents.menusMaxX.map { notch.minX - $0 })
            let right = host.rightWing == nil ? 0
                : NotchGeometry.wingWidth(available: extents.statusItemsMinX.map { $0 - notch.maxX })
            setWings(left: left, right: right)
        }
    }

    private func setWings(left: CGFloat, right: CGFloat) {
        if state.leftWingWidth != left { state.leftWingWidth = left }
        if state.rightWingWidth != right { state.rightWingWidth = right }
    }

    private func observeWingSetting() {
        withObservationTracking {
            _ = settings.showWings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateWings()
                self?.observeWingSetting()
            }
        }
    }

    // MARK: - Hotkey

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
