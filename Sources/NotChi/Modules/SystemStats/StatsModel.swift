import Foundation
import Observation

/// Samples CPU, memory and network once a second while the wings or the Stats tab are on screen.
@MainActor
@Observable
final class StatsModel {
    nonisolated static let historyLength = 60

    private(set) var cpu: Double = 0
    private(set) var memUsed: UInt64 = 0
    private(set) var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    private(set) var pressure: MemoryPressure = .normal
    private(set) var downRate: Double = 0
    private(set) var upRate: Double = 0

    private(set) var cpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []

    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var cpuSampler = CPUSampler()
    @ObservationIgnored private var memSampler = MemorySampler()
    @ObservationIgnored private var netSampler = NetworkSampler()
    @ObservationIgnored private var tabVisible = false
    @ObservationIgnored private var observing = false

    /// Begins following `Settings.showWings`; call once.
    func begin() {
        guard !observing else { return }
        observing = true
        observeWings()
        updateRunState()
    }

    func setTabVisible(_ visible: Bool) {
        tabVisible = visible
        updateRunState()
    }

    func shutdown() {
        observing = false
        tabVisible = false
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
        let shouldRun = observing && (Settings.shared.showWings || tabVisible)
        // The glanceable wings refresh every 2 s (each refresh re-lays out the panel);
        // the Stats tab, where sparklines are watched, refreshes every second.
        let interval: TimeInterval = tabVisible ? 1 : 2
        if shouldRun, let current = timer, current.timeInterval != interval {
            current.invalidate()
            timer = nil
        }
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

        Self.push(&cpuHistory, cpu)
        Self.push(&memHistory, memFraction)
        Self.push(&downHistory, downRate)
        Self.push(&upHistory, upRate)
    }

    private static func push(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > historyLength { buffer.removeFirst(buffer.count - historyLength) }
    }
}
