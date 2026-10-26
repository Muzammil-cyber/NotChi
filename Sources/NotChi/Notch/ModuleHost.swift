// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// The set of modules shown in the notch, plus the optional stash strip on top.
@MainActor
final class ModuleHost {
    /// Top-level tabs, left of the notch.
    let tabs: [NotchModule]
    /// Modules without a tab (system stats): they supply wings and header readouts and
    /// count as visible whenever the panel is open.
    let background: [NotchModule]
    /// Every module, including the panes inside Overview, in wing-priority order.
    let allModules: [NotchModule]
    let overview: OverviewModule?
    /// Persistent drop target pinned to the top of the expanded panel.
    let topAccessory: AnyView?
    /// Compact readouts in the header, left of the settings button.
    let headerAccessory: AnyView?
    /// Phone transfers take over the wings and add a card while active.
    let transfer: TransferCoordinator?

    init(tabs: [NotchModule], background: [NotchModule] = [], topAccessory: AnyView?,
         headerAccessory: AnyView? = nil, transfer: TransferCoordinator? = nil) {
        self.tabs = tabs
        self.background = background
        self.overview = tabs.lazy.compactMap { $0 as? OverviewModule }.first
        self.allModules = tabs.flatMap { tab in [tab] + ((tab as? OverviewModule)?.panes ?? []) } + background
        self.topAccessory = topAccessory
        self.headerAccessory = headerAccessory
        self.transfer = transfer
    }

    var hasWings: Bool { leftWing != nil || rightWing != nil }

    /// The default wings (the stats readouts). Only background modules supply them: tab
    /// modules' wings (Now Playing, Calendar) show only while they claim the wings.
    private(set) lazy var leftWing: AnyView? = background.lazy.compactMap { $0.makeLeftWing() }.first
    private(set) lazy var rightWing: AnyView? = background.lazy.compactMap { $0.makeRightWing() }.first

    /// The module currently claiming the wings, if any: an urgent claim (a meeting about
    /// to start) first, then module order (music before an ongoing meeting).
    var wingClaimant: NotchModule? {
        allModules.first { $0.claimsWings && $0.wingNeedsRoom } ?? allModules.first { $0.claimsWings }
    }

    private var claimedWings: [String: (left: AnyView, right: AnyView)] = [:]

    func wings(of module: NotchModule) -> (left: AnyView, right: AnyView) {
        if let wings = claimedWings[module.id] { return wings }
        let wings = (module.makeLeftWing() ?? AnyView(Color.clear), module.makeRightWing() ?? AnyView(Color.clear))
        claimedWings[module.id] = wings
        return wings
    }

    private var expandedViews: [String: AnyView] = [:]

    func expandedView(for id: String) -> AnyView {
        if let view = expandedViews[id] { return view }
        let view = tabs.first { $0.id == id }?.makeExpandedView() ?? AnyView(EmptyView())
        expandedViews[id] = view
        return view
    }

    /// Tabs the user hasn't turned off, in order.
    var enabledTabs: [NotchModule] { tabs.filter(\.isEnabled) }

    /// Maps an automation id to an enabled tab: Overview's panes ("nowplaying", "calendar")
    /// open Overview, Dev's tools ("ports") open Dev.
    func tabID(for id: String) -> String? {
        for tab in enabledTabs {
            if tab.id == id { return id }
            if let overview = tab as? OverviewModule, overview.contains(paneID: id) { return tab.id }
            if let dev = tab as? DevModule, dev.contains(toolID: id) {
                dev.select(toolID: id)
                return tab.id
            }
        }
        return nil
    }

    func startAll() { (tabs + background).forEach { $0.start() } }
    func stopAll() { (tabs + background).forEach { $0.stop() } }

    func visibilityChanged(expanded: Bool, selected: String) {
        for module in tabs {
            module.setVisible(expanded && module.id == selected)
        }
        for module in background { module.setVisible(expanded) }
    }
}
