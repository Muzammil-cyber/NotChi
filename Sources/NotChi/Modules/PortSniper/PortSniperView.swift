// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import SwiftUI

/// Expanded Port Sniper panel: header plus a compact list of listening ports.
struct PortSniperView: View {
    let model: PortModel
    @State private var settings = Settings.shared
    @State private var confirmingID: String?
    @State private var confirmTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 6) {
            header
            if model.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.entries) { entry in
                            PortRow(entry: entry, model: model, confirmingID: confirmingBinding)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .onDisappear { setConfirming(nil) }
    }

    private var confirmingBinding: Binding<String?> {
        Binding(get: { confirmingID }, set: { setConfirming($0) })
    }

    private func setConfirming(_ id: String?) {
        confirmTask?.cancel()
        confirmingID = id
        NotchState.shared.holdOpen("ports.kill", id != nil)
        guard id != nil else { return }
        confirmTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { setConfirming(nil) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(model.entries.count) listening")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Toggle("Show all", isOn: Binding(
                get: { settings.portsShowAll },
                set: { settings.portsShowAll = $0; model.applyFilter() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Button { Task { await model.refreshNow() } } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
                    .animation(.easeInOut(duration: 0.3), value: model.isRefreshing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "network.slash").font(.system(size: 22)).foregroundStyle(.white.opacity(0.3))
            Text(model.hasScanned ? "No dev servers listening" : "Scanning…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            if model.hasScanned {
                Text("Start one with `npm run dev`")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PortRow: View {
    let entry: PortEntry
    let model: PortModel
    @Binding var confirmingID: String?

    private var health: PortHealth? { model.health[entry.id] }
    private var isKilling: Bool { model.killing.contains(entry.id) }
    private var isConfirming: Bool { confirmingID == entry.id }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(String(entry.port))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if entry.container != nil {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.cyan.opacity(0.8))
                            .help("Docker container")
                    }
                    Text(entry.container?.name ?? entry.name).font(.system(size: 12, weight: .medium))
                    Text(entry.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                if let error = model.errors[entry.id] {
                    Text(error).font(.system(size: 10)).foregroundStyle(.red)
                } else {
                    Text(shortCwd).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Text(health?.summary ?? "…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(statusColor.opacity(0.9))
            buttons
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06)))
        .opacity(isKilling ? 0.4 : 1)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { open() } label: { Image(systemName: "safari") }
                .help("Open http://localhost:\(entry.port)")
            Button { reveal() } label: { Image(systemName: "folder") }
                .disabled(entry.cwd == nil || entry.container != nil)
                .help("Reveal working directory in Finder")
            if isConfirming {
                Button { confirmingID = nil; model.kill(entry) } label: {
                    Text(entry.container != nil ? "Stop?" : "Kill?").font(.system(size: 11, weight: .bold)).foregroundStyle(.red)
                }
            } else {
                Button { confirmingID = entry.id } label: {
                    Image(systemName: entry.container != nil ? "stop.circle" : "xmark.circle")
                }
                .disabled(!entry.isKillable || isKilling)
                .help(killHelp)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.65))
    }

    private var statusColor: Color {
        switch health?.status {
        case .healthy: .green
        case .slow: .yellow
        case .unresponsive: .red
        case nil: .gray
        }
    }

    private var killHelp: String {
        if let container = entry.container { return "Stop container \(container.name)" }
        return entry.isKillable ? "Kill process \(entry.pid)" : "Owned by another user"
    }

    private var shortCwd: String {
        if let container = entry.container { return "container \(container.id.prefix(12)) · via \(entry.pid > 0 ? entry.name : "Docker")" }
        guard let cwd = entry.cwd else { return entry.path }
        let home = NSHomeDirectory()
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    private func open() {
        if let url = URL(string: "http://localhost:\(entry.port)") { NSWorkspace.shared.open(url) }
    }

    private func reveal() {
        guard let cwd = entry.cwd else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
    }
}
