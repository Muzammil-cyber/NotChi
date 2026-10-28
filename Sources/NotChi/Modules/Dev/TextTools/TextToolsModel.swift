// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import Observation

/// State behind the Text tool: the input, which utility runs on it, and its output.
/// Nothing here runs in the background; the clipboard is read only when the tool is shown.
@MainActor
@Observable
final class TextToolsModel {
    var input = "" { didSet { recompute() } }
    private(set) var tool: TextTool = .json { didSet { recompute() } }
    var direction: Direction = .encode { didSet { recompute() } }
    var indent: JSONIndent = .two { didSet { recompute() } }

    private(set) var output: ToolOutput?
    private(set) var errorMessage: String?
    /// Row (or the whole output, with `Self.allID`) that was just copied, for a brief "Copied".
    private(set) var copiedID: UUID?
    static let allID = UUID()

    @ObservationIgnored private var lastPasteboardCount = -1
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    @ObservationIgnored private let settings = Settings.shared

    func setVisible(_ visible: Bool) {
        if visible { refreshFromPasteboard() }
    }

    /// Takes new clipboard content when it changed since the last look; otherwise leaves
    /// whatever the user was working on. Skips what clipboard history skips (passwords and
    /// other concealed or transient copies, and ignored apps), so secrets never show here.
    func refreshFromPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardCount else { return }
        lastPasteboardCount = pb.changeCount
        // Our own copies (a tool's result) shouldn't replace the input.
        guard pb.changeCount != Paster.ignoredChangeCount else { return }
        guard !ClipboardMonitor.isSensitive(pb),
              let text = pb.string(forType: .string), !text.isEmpty,
              text.utf8.count <= TextTransforms.maxInputBytes else { return }
        apply(text)
    }

    /// Puts explicit text (from a clipboard row) in the input and picks its tool.
    func load(text: String) {
        lastPasteboardCount = NSPasteboard.general.changeCount
        apply(text)
    }

    private func apply(_ text: String) {
        let detected = settings.textToolsAutoDetect ? TextToolsDetector.detect(text) : nil
        // One recompute for the pair: set the tool without triggering a run on the old input.
        if let detected, detected != tool {
            tool = detected
        }
        if tool.hasDirection { direction = Self.autoDirection(for: tool, text: text) }
        input = text
    }

    func select(_ newTool: TextTool) {
        if newTool.hasDirection { direction = Self.autoDirection(for: newTool, text: input) }
        tool = newTool
    }

    /// Decode what looks encoded, encode the rest.
    private static func autoDirection(for tool: TextTool, text: String) -> Direction {
        switch tool {
        case .base64: TextToolsDetector.isBase64(text) ? .decode : .encode
        case .url: TextToolsDetector.detect(text) == .url ? .decode : .encode
        default: .encode
        }
    }

    func generateUUID() {
        tool = .uuid
        input = UUID().uuidString.lowercased()
    }

    func useOutputAsInput() {
        guard let text = output?.copyText else { return }
        input = text
    }

    func clear() { input = "" }

    func copy(_ text: String, id: UUID) {
        Paster.copy(text: text)
        copiedID = id
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { copiedID = nil }
        }
    }

    private func recompute() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            output = nil
            errorMessage = nil
            return
        }
        switch TextTransforms.run(tool, input: input, direction: direction, indent: indent) {
        case .success(let result):
            output = result
            errorMessage = nil
        case .failure(let error):
            output = nil
            errorMessage = error.message
        }
    }
}
