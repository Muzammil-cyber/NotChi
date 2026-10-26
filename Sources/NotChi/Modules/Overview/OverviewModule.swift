// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// The "Overview" tab: smaller modules (Now Playing, Calendar) shown side by side.
/// A pane turned off in Settings is left out and the others take its room.
@MainActor
final class OverviewModule: NotchModule {
    let id = "overview"
    let title = "Overview"
    let systemImage = "square.grid.2x2"

    let panes: [NotchModule]
    private var visible = false
    private var views: [String: AnyView] = [:]

    init(panes: [NotchModule]) {
        self.panes = panes
    }

    /// Panes the user hasn't turned off, in display order.
    var enabledPanes: [NotchModule] { panes.filter(\.isEnabled) }

    func contains(paneID: String) -> Bool { panes.contains { $0.id == paneID } }

    func view(for pane: NotchModule) -> AnyView {
        if let view = views[pane.id] { return view }
        let view = pane.makeExpandedView()
        views[pane.id] = view
        return view
    }

    func makeExpandedView() -> AnyView { AnyView(OverviewView(module: self)) }

    func start() { panes.forEach { $0.start() } }
    func stop() { panes.forEach { $0.stop() } }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        syncVisibility()
    }

    /// Also called when a pane is turned on or off.
    func syncVisibility() {
        for pane in panes { pane.setVisible(visible && pane.isEnabled) }
    }
}

private struct OverviewView: View {
    let module: OverviewModule

    var body: some View {
        let panes = module.enabledPanes
        HStack(spacing: 0) {
            if panes.isEmpty {
                Text("Turn on Now Playing or Calendar in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                if index > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 1)
                        .padding(.vertical, 12)
                }
                module.view(for: pane)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: panes.map(\.id)) { _, _ in module.syncVisibility() }
    }
}
