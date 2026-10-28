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
            HStack(spacing: 5) {
                Image(systemName: model.tool.systemImage).font(.system(size: 11))
                Text(model.tool.title).font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).opacity(0.5)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
                optionLabel(model.indent.title)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        case .base64, .url:
            Button { model.direction = model.direction.flipped } label: {
                HStack(spacing: 4) {
                    Text(model.direction.title)
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 9))
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .uuid:
            Button { model.generateUUID() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                    Text("New")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .jwt, .time, .hash, .color:
            EmptyView()
        }
    }

    private func optionLabel(_ text: String) -> some View {
        HStack(spacing: 3) {
            Text(text)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold))
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.6))
        .frame(height: 24)
    }

    private var moreMenu: some View {
        Menu {
            Button("Use result as input") { model.useOutputAsInput() }.disabled(model.output == nil)
            Button("Clear") { model.clear() }.disabled(model.input.isEmpty)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var copyButton: some View {
        let copied = model.copiedID == TextToolsModel.allID
        return Button {
            if let text = model.output?.copyText { model.copy(text, id: TextToolsModel.allID) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                Text(copied ? "Copied" : "Copy").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(model.output == nil ? 0.35 : 0.95))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.white.opacity(model.output == nil ? 0.06 : 0.18), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.output == nil)
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
