// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

extension View {
    /// A capsule of Liquid Glass behind a small control (macOS 26+), or a translucent fill
    /// before that. For controls only; content (lists, text panes) stays on plain fills.
    /// `prominent` is for the one primary action in a group.
    func notchGlass(prominent: Bool = false) -> some View {
        modifier(NotchGlassBackground(prominent: prominent))
    }
}

private struct NotchGlassBackground: ViewModifier {
    let prominent: Bool
    /// Glass drawn while the panel is still fading in renders flat (see ModuleTabBar), so
    /// it starts as a plain fill and turns to glass once the panel is in.
    @State private var ready = false

    func body(content: Content) -> some View {
        content
            .background { fill }
            .task {
                try? await Task.sleep(for: .milliseconds(320))
                ready = true
            }
    }

    @ViewBuilder private var fill: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), ready {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.tint(.white.opacity(prominent ? 0.24 : 0.08)).interactive(), in: .capsule)
        } else {
            plain
        }
        #else
        plain
        #endif
    }

    private var plain: some View {
        Capsule().fill(Color.white.opacity(prominent ? 0.18 : 0.08))
    }
}
