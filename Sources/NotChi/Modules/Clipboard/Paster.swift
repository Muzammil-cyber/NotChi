// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit

/// Writes history items back to the pasteboard and optionally pastes them into the previous app.
@MainActor
enum Paster {
    /// Change count of the last pasteboard write made by NotChi; the monitor skips it.
    static var ignoredChangeCount = -1

    /// Copies the item to the pasteboard without pasting.
    static func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .code, .link:
            pb.setString(item.text ?? "", forType: .string)
        case .richText:
            if let rtf = item.rtf { pb.setData(rtf, forType: .rtf) }
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let url = item.imageURL, let png = try? Data(contentsOf: url) {
                pb.setData(png, forType: .png)
                if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .file:
            pb.writeObjects((item.fileURLs ?? []).map { $0 as NSURL })
        }
        ignoredChangeCount = pb.changeCount
    }

    /// Copies, collapses the notch, then sends Cmd+V when allowed. Returns whether it will auto-paste.
    @discardableResult
    static func paste(_ item: ClipItem) -> Bool {
        copy(item)
        NotchController.shared.collapse()
        guard Permissions.isAccessibilityTrusted else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { postCommandV() }
        return true
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
