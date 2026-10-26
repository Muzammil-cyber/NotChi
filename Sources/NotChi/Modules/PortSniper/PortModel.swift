// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Darwin
import Foundation
import Observation

/// State for the Port Sniper tab: scans listeners, pings them, and kills processes.
/// Polling runs only while the tab is visible.
@MainActor
@Observable
final class PortModel {
    private(set) var entries: [PortEntry] = []
    private(set) var health: [String: PortHealth] = [:]
    private(set) var killing: Set<String> = []
    private(set) var errors: [String: String] = [:]
    private(set) var hasScanned = false
    private(set) var isRefreshing = false

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let settings = Settings.shared
    @ObservationIgnored private var allEntries: [PortEntry] = []

    func setVisible(_ visible: Bool) {
        loop?.cancel()
        loop = nil
        guard visible else { return }
        loop = Task { [weak self] in
            var cycle = 0
            while !Task.isCancelled {
                // Rescan every 3 s (cheap, ~5 ms); ping every other cycle; re-check HTTP
                // status every 30 s since it rarely changes.
                await self?.refresh(ping: cycle % 2 == 0, checkHTTP: cycle % 10 == 0)
                cycle += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Re-applies the Show all filter after the setting changes.
    func applyFilter() {
        setIfChanged(\.entries, filtered(allEntries))
    }

    /// Manual refresh from the header button: full check, with the spinner.
    func refreshNow() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await refresh(ping: true, checkHTTP: true)
    }

    func refresh(ping: Bool = true, checkHTTP: Bool = true) async {
        allEntries = await PortScanner.scan()
        let list = filtered(allEntries)
        setIfChanged(\.entries, list)
        if !hasScanned { hasScanned = true }
        let alive = Set(list.map(\.id))
        setIfChanged(\.health, health.filter { alive.contains($0.key) })
        setIfChanged(\.errors, errors.filter { alive.contains($0.key) })
        guard ping else { return }

        let known = health
        let results = await withTaskGroup(of: (String, PortHealth).self) { group in
            for e in list {
                // New ports always get an HTTP check so the status shows right away.
                let http = checkHTTP || known[e.id] == nil
                let previous = known[e.id]?.httpStatus
                group.addTask {
                    (e.id, await HealthPinger.ping(port: e.port, ipv6Only: e.hasIPv6 && !e.hasIPv4,
                                                   checkHTTP: http, knownStatus: previous))
                }
            }
            var out: [String: PortHealth] = [:]
            for await (id, h) in group { out[id] = h }
            return out
        }
        var updated = health
        for (id, h) in results where alive.contains(id) { updated[id] = h }
        setIfChanged(\.health, updated)
    }

    /// Assigning an equal value still invalidates SwiftUI views, so skip no-op writes.
    private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<PortModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    private func filtered(_ list: [PortEntry]) -> [PortEntry] {
        let shown = settings.portsShowAll ? list : list.filter(PortFilter.looksLikeDevServer)
        return shown.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Stops the container for Docker ports; otherwise SIGTERM, then SIGKILL after 2 s.
    func kill(_ entry: PortEntry) {
        let id = entry.id
        errors[id] = nil
        if let container = entry.container {
            killing.insert(id)
            Task { [weak self] in
                let stopped = await Task.detached { DockerClient.stop(id: container.id) }.value
                self?.killing.remove(id)
                if !stopped { self?.errors[id] = "Couldn't stop container \(container.name)" }
                await self?.refresh()
            }
            return
        }
        guard Darwin.kill(entry.pid, SIGTERM) == 0 else {
            errors[id] = errno == EPERM ? "Not permitted (owned by another user)" : "Kill failed (errno \(errno))"
            return
        }
        killing.insert(id)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if Darwin.kill(entry.pid, 0) == 0 { _ = Darwin.kill(entry.pid, SIGKILL) }
            try? await Task.sleep(for: .milliseconds(300))
            self?.killing.remove(id)
            await self?.refresh()
        }
    }
}
