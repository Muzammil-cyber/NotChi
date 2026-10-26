// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Live CPU, memory and network stats: readouts in the wings and in the panel header.
/// Not a tab of its own: the host runs it as a background module.
@MainActor
final class SystemStatsModule: NotchModule {
    let id = "stats"
    let title = "Stats"
    let systemImage = "gauge.with.dots.needle.33percent"

    private let model = StatsModel()

    func makeExpandedView() -> AnyView { AnyView(EmptyView()) }
    func makeHeaderView() -> AnyView { AnyView(StatsHeaderView(model: model)) }
    func makeLeftWing() -> AnyView? { AnyView(StatsLeftWing(model: model)) }
    func makeRightWing() -> AnyView? { AnyView(StatsRightWing(model: model)) }

    func start() { model.begin() }
    func stop() { model.shutdown() }
    /// True while the panel is open, so the header readouts stay live.
    func setVisible(_ visible: Bool) { model.setPanelVisible(visible) }
}
