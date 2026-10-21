import SwiftUI

/// Clipboard history with quick paste, plus the file/text stash strip.
@MainActor
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let title = "Clipboard"
    let systemImage = "doc.on.clipboard"

    private let store = ClipboardStore()
    private let monitor = ClipboardMonitor()
    private let stash = StashStore()

    init() {
        monitor.onItem = { [store] item in store.add(item) }
    }

    func start() { monitor.start() }

    func stop() {
        monitor.stop()
        store.saveNow()
        stash.shutdown()
    }

    func makeExpandedView() -> AnyView { AnyView(ClipboardView(store: store)) }
    func makeStashView() -> AnyView { AnyView(StashDropView(store: stash)) }
}
