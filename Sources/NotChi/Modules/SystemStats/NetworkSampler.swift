// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Darwin
import Foundation

/// Measures aggregate network throughput over all active, non-loopback interfaces.
struct NetworkSampler {
    private var previous: (rx: UInt64, tx: UInt64, time: TimeInterval)?

    /// Returns (download, upload) in bytes per second since the previous call; zeros on the first call or a counter reset.
    mutating func sample() -> (down: Double, up: Double) {
        guard let totals = Self.readTotals() else { return (0, 0) }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (totals.rx, totals.tx, now) }
        guard let prev = previous else { return (0, 0) }
        let dt = now - prev.time
        guard dt > 0, totals.rx >= prev.rx, totals.tx >= prev.tx else { return (0, 0) }
        return (Double(totals.rx - prev.rx) / dt, Double(totals.tx - prev.tx) / dt)
    }

    /// Cumulative received / sent bytes via the routing-table interface list.
    private static func readTotals() -> (rx: UInt64, tx: UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let msgLen = Int(header.ifm_msglen)
                guard msgLen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = Int32(info.ifm_flags)
                    if flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
                        rx &+= info.ifm_data.ifi_ibytes
                        tx &+= info.ifm_data.ifi_obytes
                    }
                }
                offset += msgLen
            }
        }
        return (rx, tx)
    }
}
