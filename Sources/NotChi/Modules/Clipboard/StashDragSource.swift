import AppKit
import SwiftUI

/// AppKit drag source for stash chips. SwiftUI's `onDrag` never says whether a drop
/// succeeded; `NSDraggingSource` does, which is what lets a chip disappear once it has
/// been dropped somewhere else. It also handles click (copy) and the right-click menu,
/// since it sits on top of the chip and receives those events.
struct StashDragSource: NSViewRepresentable {
    var writer: () -> NSPasteboardWriting?
    var preview: () -> NSImage?
    var onClick: () -> Void
    var menu: () -> NSMenu
    /// Called when the drag ends; `true` when another app or Finder accepted the drop.
    var onDragEnd: (_ droppedElsewhere: Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.source = self
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var source: StashDragSource?
        private var mouseDownEvent: NSEvent?
        private var dragging = false

        // The panel is usually not key; respond to the very first click.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragging, let start = mouseDownEvent, let source else { return }
            let dx = event.locationInWindow.x - start.locationInWindow.x
            let dy = event.locationInWindow.y - start.locationInWindow.y
            guard dx * dx + dy * dy > 9, let writer = source.writer() else { return }
            dragging = true

            let item = NSDraggingItem(pasteboardWriter: writer)
            let image = source.preview() ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
            let size = NSSize(width: 48, height: 48)
            let origin = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: origin.x - size.width / 2, y: origin.y - size.height / 2,
                                         width: size.width, height: size.height), contents: image)
            NotchState.shared.holdOpen("stash-drag", true)
            beginDraggingSession(with: [item], event: start, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if !dragging { source?.onClick() }
            mouseDownEvent = nil
        }

        override func menu(for event: NSEvent) -> NSMenu? { source?.menu() }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .generic] : .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            dragging = false
            mouseDownEvent = nil
            NotchState.shared.holdOpen("stash-drag", false)
            // Dropping back onto NotChi itself (e.g. the stash strip) doesn't count as "used".
            let ontoNotch = window?.frame.contains(screenPoint) ?? false
            source?.onDragEnd(!operation.isEmpty && !ontoNotch)
        }
    }
}

/// NSMenuItem that runs a closure, so SwiftUI-side code can build AppKit menus inline.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}
