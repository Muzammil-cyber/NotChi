// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Clipboard history with quick paste, plus the file/text stash strip.
@MainActor
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let title = "Clipboard"
    let systemImage = "doc.on.clipboard"

    private let store = ClipboardStore()
    private let monitor = ClipboardMonitor()
    /// Shared with phone transfer, which drops received files into the stash.
    let stash = StashStore()

    init() {
        monitor.onItem = { [store] item in store.add(item) }
    }

    func start() {
        monitor.start()
        observeLimit()
    }

    func stop() {
        monitor.stop()
        stash.shutdown()
    }

    func setVisible(_ visible: Bool) { store.setVisible(visible) }

    /// Trims the history right away when the limit is lowered in Settings.
    private func observeLimit() {
        withObservationTracking {
            _ = Settings.shared.clipboardLimit
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.store.applyLimit()
                self?.observeLimit()
            }
        }
    }

    func makeExpandedView() -> AnyView { AnyView(ClipboardView(store: store)) }
    func makeStashView() -> AnyView { AnyView(StashDropView(store: stash)) }
}
