// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// A row of tabs: inactive tabs show only their icon, the active tab its icon and title.
/// The row sits in a quiet capsule track; one selection pill slides to the active tab, and
/// on macOS 26+ it's Liquid Glass.
struct ModuleTabBar: View {
    let modules: [NotchModule]
    let selectedID: String
    /// Show the active tab's title; turned off when even that doesn't fit.
    var showsSelectedTitle = true
    let onSelect: (String) -> Void

    @Namespace private var namespace
    /// Glass drawn while the panel is still fading in renders flat and stays that way, so
    /// the pill starts as a plain fill and switches to glass once the panel is fully in.
    @State private var glassReady = false

    var body: some View {
        // No GlassEffectContainer: there's only one glass shape, and a container would draw
        // it above the labels instead of behind them.
        row.task {
            try? await Task.sleep(for: .milliseconds(320))
            glassReady = true
        }
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(modules, id: \.id) { module in
                let selected = module.id == selectedID
                Button {
                    guard !selected else { return }
                    onSelect(module.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: module.systemImage)
                        if selected && showsSelectedTitle {
                            // Opacity only: scaling text re-rasterizes it every frame.
                            Text(module.title)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                    // Each tab only marks where the pill should go.
                    .background(Color.clear.matchedGeometryEffect(id: module.id, in: namespace, isSource: true))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(module.title)
                .accessibilityLabel(module.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            if modules.contains(where: { $0.id == selectedID }) {
                SelectionPill(glass: glassReady)
                    .matchedGeometryEffect(id: selectedID, in: namespace, properties: .frame, isSource: false)
            }
        }
        // A plain track (not glass: the pill is the only glass, and glass can't sit on glass)
        // groups the tabs into one control, like a macOS segmented control.
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

/// The single pill behind the active tab. It's one persistent view whose frame animates,
/// so a selection change slides it across instead of fading one out and another in.
private struct SelectionPill: View {
    let glass: Bool

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), glass {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(.white.opacity(0.14)).interactive(), in: .capsule)
        } else {
            plain
        }
        #else
        plain
        #endif
    }

    private var plain: some View {
        Capsule().fill(Color.white.opacity(0.16))
    }
}
