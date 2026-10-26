// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

/// Searchable clipboard history list with type filters and keyboard navigation.
struct ClipboardView: View {
    let store: ClipboardStore

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", text = "Text", code = "Code", links = "Links", images = "Images", files = "Files"
        var id: String { rawValue }

        var storeFilter: ClipboardStore.KindFilter {
            switch self {
            case .all: .all
            case .text: .kinds([.text, .richText])
            case .code: .kinds([.code])
            case .links: .kinds([.link])
            case .images: .kinds([.image])
            case .files: .kinds([.file])
            }
        }
    }

    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var selection: UUID?
    private let accessibility = AccessibilityStatus.shared
    @State private var needsAccessibilityHint = false
    @FocusState private var searchFocused: Bool

    /// Filtering, search and ordering (pinned first) happen in the store's SQL query.
    private var visible: [ClipItem] { store.results }

    var body: some View {
        VStack(spacing: 6) {
            header
            if needsAccessibilityHint && !accessibility.isTrusted { accessibilityBanner }
            content
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { pasteSelected(); return .handled }
        .onKeyPress(.escape) {
            if searchFocused || !query.isEmpty { query = ""; searchFocused = false; return .handled }
            return .ignored
        }
        .background(quickPasteShortcuts)
        .onChange(of: searchFocused) { _, focused in
            NotchState.shared.holdOpen("clipboard-search", focused)
            if focused { NotchController.shared.focusPanel() }
        }
        .onChange(of: query) { _, _ in runSearch() }
        .onChange(of: filter) { _, _ in runSearch() }
        .onAppear { store.search(query, filter: filter.storeFilter) }
        .onDisappear { NotchState.shared.holdOpen("clipboard-search", false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                TextField("Search clipboard", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onSubmit { pasteSelected() }
            }
            .padding(.horizontal, 8)
            .frame(width: 190, height: 24)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                NotchController.shared.focusPanel()
                searchFocused = true
            }

            ForEach(Filter.allCases) { f in
                Button { filter = f } label: {
                    Text(f.rawValue)
                        .font(.system(size: 11, weight: filter == f ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(filter == f ? 1 : 0.55))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.white.opacity(filter == f ? 0.16 : 0), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if store.hasUnpinned {
                Button("Clear") { store.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").font(.system(size: 10))
            Text("Copied. Allow Accessibility to paste automatically.").font(.system(size: 11))
            Spacer()
            Button("Enable") {
                Permissions.requestAccessibility()
                AppDelegate.shared?.showSettings(tab: .permissions)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.white.opacity(0.18), in: Capsule())
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: List

    @ViewBuilder private var content: some View {
        let items = visible
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 22))
                Text(store.isEmpty ? "Nothing copied yet" : "No matches").font(.system(size: 12))
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item, selected: selection == item.id, shortcut: index < 9 ? index + 1 : nil, now: now,
                                    onPaste: { paste(item) },
                                    onPin: { store.togglePin(item) },
                                    onDelete: { store.delete(item) })
                                .id(item.id)
                                .onAppear { if index == items.count - 1 { store.loadMore() } }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: selection) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } }
                }
            }
            }
        }
    }

    /// Invisible buttons that provide Cmd+1...9.
    private var quickPasteShortcuts: some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button("") {
                    let items = visible
                    if n <= items.count { paste(items[n - 1]) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        let items = visible
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : items.count)
        selection = items[min(max(current + delta, 0), items.count - 1)].id
    }

    private func pasteSelected() {
        let items = visible
        if let item = items.first(where: { $0.id == selection }) ?? items.first { paste(item) }
    }

    private func runSearch() {
        store.search(query, filter: filter.storeFilter)
        selection = visible.first?.id
    }

    private func paste(_ item: ClipItem) {
        // List rows are trimmed (no RTF, capped text); paste the complete item.
        needsAccessibilityHint = !Paster.paste(store.fullItem(item))
        searchFocused = false
    }
}

private struct ClipRow: View {
    /// Coarse age label: "now", "5m", "3h", "2d", then a date.
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86400): return "\(Int(seconds / 86400))d"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    let item: ClipItem
    let selected: Bool
    let shortcut: Int?
    /// Supplied by a once-a-minute timeline; a self-updating relative `Text` would redraw every second.
    let now: Date
    let onPaste: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            leading.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 12, design: item.kind == .code ? .monospaced : .default))
                    .lineLimit(item.kind == .image ? 1 : 2)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if let name = item.sourceName { Text(name) }
                    Text(Self.age(of: item.date, now: now))
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            }
            if hovering {
                HStack(spacing: 2) {
                    actionButton(item.pinned ? "pin.slash" : "pin", action: onPin)
                    actionButton("trash", action: onDelete)
                }
            } else {
                if item.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                }
                if let shortcut {
                    Text("⌘\(shortcut)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 36)
        .background(.white.opacity(selected ? 0.16 : hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onPaste)
    }

    @ViewBuilder private var leading: some View {
        if item.kind == .image, let url = item.imageURL, let image = Thumbnails.image(at: url, maxPixel: 80) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: item.systemImage).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func actionButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
