// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Foundation
import Observation

/// Samples CPU, memory and network every 2 s while the wings or the panel header show them.
@MainActor
@Observable
final class StatsModel {
    private(set) var cpu: Double = 0
    private(set) var memUsed: UInt64 = 0
    private(set) var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    private(set) var pressure: MemoryPressure = .normal
    private(set) var downRate: Double = 0
    private(set) var upRate: Double = 0

    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var cpuSampler = CPUSampler()
    @ObservationIgnored private var memSampler = MemorySampler()
    @ObservationIgnored private var netSampler = NetworkSampler()
    @ObservationIgnored private var panelVisible = false
    @ObservationIgnored private var observing = false

    /// Begins following `Settings.showWings`; call once.
    func begin() {
        guard !observing else { return }
        observing = true
        observeWings()
        updateRunState()
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        updateRunState()
    }

    func shutdown() {
        observing = false
        panelVisible = false
        timer?.invalidate()
        timer = nil
    }

    private func observeWings() {
        guard observing else { return }
        withObservationTracking {
            _ = Settings.shared.showWings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing else { return }
                self.updateRunState()
                self.observeWings()
            }
        }
    }

    private func updateRunState() {
        let shouldRun = observing && (Settings.shared.showWings || panelVisible)
        // Glanceable numbers: every 2 s is enough, and each refresh re-lays out the panel.
        let interval: TimeInterval = 2
        if shouldRun, timer == nil {
            tick()
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = interval * 0.1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !shouldRun, timer != nil {
            timer?.invalidate()
            timer = nil
            // Counters keep moving while stopped; restart baselines so the first rate is not an average over the gap.
            cpuSampler = CPUSampler()
            netSampler = NetworkSampler()
        }
    }

    private func tick() {
        cpu = cpuSampler.sample()
        memTotal = memSampler.total
        memUsed = memSampler.usedBytes()
        pressure = memSampler.pressure()
        let net = netSampler.sample()
        downRate = net.down
        upRate = net.up
    }
}
