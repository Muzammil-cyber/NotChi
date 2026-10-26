// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// A module's request to show its wings beside the collapsed notch instead of the stats.
struct WingClaim: Equatable {
    /// Brief and important (an event about to start): takes priority over other claims and
    /// gets room beside the notch even where the stats wings stepped aside for menus.
    var urgent = false
    /// Width of each wing; nil uses the stats wings' width. Compact content (artwork, an
    /// icon) should hug the notch rather than float in a wide black bar.
    var width: CGFloat?
}

/// A feature that lives inside the notch. Each module owns its own state and views;
/// the shell only decides where and when those views are shown.
///
/// A module is either a tab (left of the notch), a child of a container tab (Overview's
/// panes, Dev's tools), or a background module (stats). See ARCHITECTURE.md.
@MainActor
protocol NotchModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }

    /// Main content shown when this module's tab is selected in the expanded panel.
    func makeExpandedView() -> AnyView

    /// Optional compact views drawn beside the hardware notch while collapsed: always for a
    /// background module, only while `wingClaim` is set for any other.
    func makeLeftWing() -> AnyView?
    func makeRightWing() -> AnyView?

    /// Non-nil while this module wants the collapsed wings (music playing, an event about
    /// to start). Read from SwiftUI bodies, so back it with observable state.
    var wingClaim: WingClaim? { get }
    /// False when the user turned the module off; it's then hidden and does no work.
    var isEnabled: Bool { get }

    /// Modules shown inside this one (a container tab's panes or tools); empty otherwise.
    /// The host starts, stops and routes to them through the container.
    var children: [NotchModule] { get }
    /// Brings the child with this id on screen (e.g. switches Dev to that tool).
    func reveal(childID: String)

    /// Called once at launch and before quit.
    func start()
    func stop()

    /// Called when this module's tab becomes visible / hidden in the expanded panel.
    /// Use it to throttle work that is only needed on screen.
    func setVisible(_ visible: Bool)
}

extension NotchModule {
    func makeLeftWing() -> AnyView? { nil }
    func makeRightWing() -> AnyView? { nil }
    var wingClaim: WingClaim? { nil }
    var isEnabled: Bool { true }
    var children: [NotchModule] { [] }
    func reveal(childID: String) {}
    func start() {}
    func stop() {}
    func setVisible(_ visible: Bool) {}
}
