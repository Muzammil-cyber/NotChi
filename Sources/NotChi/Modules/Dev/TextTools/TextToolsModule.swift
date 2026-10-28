// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Developer text utilities (JSON, JWT, Base64, URL, Time, Hash, UUID, Color) that act on
/// the clipboard. The tool is picked from what was copied.
@MainActor
final class TextToolsModule: NotchModule {
    let id = "texttools"
    let title = "Text"
    let systemImage = "wand.and.stars"

    let model = TextToolsModel()

    init() {}

    func makeExpandedView() -> AnyView { AnyView(TextToolsView(model: model)) }

    func setVisible(_ visible: Bool) { model.setVisible(visible) }
}
