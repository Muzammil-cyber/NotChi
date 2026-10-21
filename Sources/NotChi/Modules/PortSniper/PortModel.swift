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
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Re-applies the Show all filter after the setting changes.
    func applyFilter() {
        entries = filtered(allEntries)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        allEntries = await PortScanner.scan()
        let list = filtered(allEntries)
        entries = list
        hasScanned = true
        let alive = Set(list.map(\.id))
        health = health.filter { alive.contains($0.key) }
        errors = errors.filter { alive.contains($0.key) }

        let results = await withTaskGroup(of: (String, PortHealth).self) { group in
            for e in list {
                group.addTask { (e.id, await HealthPinger.ping(port: e.port, ipv6Only: e.hasIPv6 && !e.hasIPv4)) }
            }
            var out: [String: PortHealth] = [:]
            for await (id, h) in group { out[id] = h }
            return out
        }
        for (id, h) in results where alive.contains(id) { health[id] = h }
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
