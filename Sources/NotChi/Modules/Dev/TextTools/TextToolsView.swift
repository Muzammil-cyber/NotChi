// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import SwiftUI

/// Expanded Text tool: a tool menu and Copy on top, input on the left, result on the right.
struct TextToolsView: View {
    let model: TextToolsModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 8) {
                inputPane
                outputPane
            }
        }
        .padding(.horizontal, 6)
        .onChange(of: inputFocused) { _, focused in
            NotchState.shared.holdOpen("texttools-input", focused)
            if focused { NotchController.shared.focusPanel() }
        }
        .onDisappear { NotchState.shared.holdOpen("texttools-input", false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            toolMenu
            toolOption
            Spacer()
            moreMenu
            copyButton
        }
        .frame(height: 24)
    }

    private var toolMenu: some View {
        Menu {
            ForEach(TextTool.allCases) { tool in
                Button { model.select(tool) } label: { Label(tool.title, systemImage: tool.systemImage) }
            }
        } label: {
            dropdownLabel(model.tool.title, systemImage: model.tool.systemImage, emphasized: true)
        }
        .dropdownStyle()
        .help("Choose a tool")
    }

    /// The one tool-specific control, only for tools that have a choice to make.
    @ViewBuilder private var toolOption: some View {
        switch model.tool {
        case .json:
            Menu {
                Picker("Indent", selection: Binding(get: { model.indent }, set: { model.indent = $0 })) {
                    ForEach(JSONIndent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                dropdownLabel(model.indent.title)
            }
            .dropdownStyle()
            .help("Indentation")
        case .base64, .url:
            Button { model.direction = model.direction.flipped } label: {
                controlLabel(model.direction.title, trailingSymbol: "arrow.left.arrow.right")
            }
            .buttonStyle(.plain)
            .help("Switch between encode and decode")
        case .uuid:
            Button { model.generateUUID() } label: {
                controlLabel("New", leadingSymbol: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Generate a new UUID")
        case .jwt, .time, .hash, .color:
            EmptyView()
        }
    }

    /// A glass capsule with a chevron, so it reads as a pop-up menu.
    private func dropdownLabel(_ title: String, systemImage: String? = nil, emphasized: Bool = false) -> some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 11)) }
            Text(title).font(.system(size: emphasized ? 12 : 11, weight: emphasized ? .semibold : .regular))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
        }
        .foregroundStyle(.white.opacity(emphasized ? 0.95 : 0.75))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .notchGlass()
        .contentShape(Capsule())
    }

    private func controlLabel(_ title: String, leadingSymbol: String? = nil, trailingSymbol: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let leadingSymbol { Image(systemName: leadingSymbol).font(.system(size: 9, weight: .semibold)) }
            Text(title).font(.system(size: 11))
            if let trailingSymbol { Image(systemName: trailingSymbol).font(.system(size: 9, weight: .semibold)) }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .notchGlass()
        .contentShape(Capsule())
    }

    private var moreMenu: some View {
        Menu {
            Button("Use result as input") { model.useOutputAsInput() }.disabled(model.output == nil)
            Button("Clear") { model.clear() }.disabled(model.input.isEmpty)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                .frame(width: 24, height: 24)
                .notchGlass()
                .contentShape(Capsule())
        }
        .dropdownStyle()
        .help("More")
    }

    private var copyButton: some View {
        let copied = model.copiedID == TextToolsModel.allID
        return Button {
            if let text = model.output?.copyText { model.copy(text, id: TextToolsModel.allID) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .semibold))
                Text(copied ? "Copied" : "Copy").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(model.output == nil ? 0.35 : 1))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .notchGlass(prominent: model.output != nil)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.output == nil)
        .help("Copy result (⌘↩)")
    }

    // MARK: Panes

    private var inputPane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { model.input }, set: { model.input = $0 }))
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .foregroundStyle(.white.opacity(0.9))
                .focused($inputFocused)
                .padding(4)
            if model.input.isEmpty {
                Text("Copy something, or type here")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 9).padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
    }

    private var outputPane: some View {
        ScrollView {
            if let output = model.output {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(output.rows) { row in
                        ToolResultRow(row: row, copied: model.copiedID == row.id) { model.copy(row.value, id: row.id) }
                    }
                }
                .padding(4)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    /// Shows a Menu's label exactly as drawn (the borderless style flattens it and drops
    /// backgrounds), without the system's own indicator since the label has a chevron.
    func dropdownStyle() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

/// One result line. Short rows copy on click; multi-line blocks (JSON, decoded text) are
/// selectable and copied with the Copy button.
private struct ToolResultRow: View {
    let row: ToolRow
    let copied: Bool
    let onCopy: () -> Void
    @State private var hovering = false

    var body: some View {
        if row.isBlock && row.label == nil {
            Text(row.value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 4)
        } else {
            Button(action: onCopy) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let label = row.label {
                HStack(spacing: 5) {
                    if let swatch = row.swatch, swatch.count == 4 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.sRGB, red: swatch[0], green: swatch[1], blue: swatch[2], opacity: swatch[3]))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                            .frame(width: 12, height: 12)
                    }
                    Text(label).lineLimit(1)
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 74, alignment: .leading)
            }
            Text(row.value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            if copied {
                Text("Copied").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            } else if let tag = row.tag {
                Text(tag).font(.system(size: 10))
                    .foregroundStyle(row.tagIsWarning ? Color.red.opacity(0.85) : .white.opacity(0.4))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.white.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
