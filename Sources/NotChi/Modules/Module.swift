// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// A feature that lives inside the notch. Each module owns its own state and views;
/// the shell only decides where and when those views are shown.
@MainActor
protocol NotchModule: AnyObject {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }

    /// Main content shown when this module's tab is selected in the expanded panel.
    func makeExpandedView() -> AnyView

    /// Optional compact views drawn beside the hardware notch while collapsed.
    func makeLeftWing() -> AnyView?
    func makeRightWing() -> AnyView?

    /// True while this module wants the collapsed wings for itself (music playing, a meeting
    /// about to start). Read from SwiftUI bodies, so back it with observable state.
    var claimsWings: Bool { get }
    /// A claim brief and important enough to take room beside the notch even where
    /// the stats wings have stepped aside for menus.
    var wingNeedsRoom: Bool { get }
    /// Width of each wing while this module claims them; nil uses the stats wings' width.
    /// Compact content (artwork, an equalizer) should hug the notch instead of floating in
    /// a wide black bar.
    var claimedWingWidth: CGFloat? { get }
    /// False when the user turned the module off; it's then hidden from the tab bars.
    var isEnabled: Bool { get }

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
    var claimsWings: Bool { false }
    var wingNeedsRoom: Bool { false }
    var claimedWingWidth: CGFloat? { nil }
    var isEnabled: Bool { true }
    func start() {}
    func stop() {}
    func setVisible(_ visible: Bool) {}
}
