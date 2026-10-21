import Darwin

/// Computes total CPU utilisation (0...1) from deltas of the host's cumulative tick counters.
struct CPUSampler {
    private var previous: [UInt32]?

    /// Returns usage since the previous call, or 0 on the first call.
    mutating func sample() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { previous = ticks }
        guard let prev = previous else { return 0 }

        let delta = zip(ticks, prev).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return 0 }
        let idle = delta[Int(CPU_STATE_IDLE)]
        return min(1, max(0, (total - idle) / total))
    }
}
