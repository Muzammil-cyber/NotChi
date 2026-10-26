// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Foundation
import Network

/// Result of probing one local port.
struct PortHealth: Sendable, Equatable {
    enum Status: Sendable { case healthy, slow, unresponsive }

    var status: Status
    /// TCP connect latency in milliseconds, nil when unresponsive.
    var latencyMs: Double?
    /// HTTP status of a HEAD request, nil for non-HTTP services.
    var httpStatus: Int?

    static let unresponsive = PortHealth(status: .unresponsive, latencyMs: nil, httpStatus: nil)

    var summary: String {
        guard let ms = latencyMs else { return "no response" }
        let time = ms < 1 ? "<1 ms" : "\(Int(ms.rounded())) ms"
        if let code = httpStatus { return "HTTP \(code) · \(time)" }
        return time
    }
}

/// Measures TCP connect latency (and optionally an HTTP HEAD status) for local ports.
enum HealthPinger {
    static let healthyThresholdMs = 50.0
    private static let timeout: Duration = .seconds(1)

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// TCP connect latency, plus an HTTP HEAD status when `checkHTTP` (that request is the
    /// costly part, so callers reuse the previous status most of the time).
    static func ping(port: UInt16, ipv6Only: Bool, checkHTTP: Bool = true, knownStatus: Int? = nil) async -> PortHealth {
        let host = ipv6Only ? "::1" : "127.0.0.1"
        guard let latency = await connect(host: host, port: port) else { return .unresponsive }
        let code = checkHTTP ? await headStatus(host: ipv6Only ? "[::1]" : "127.0.0.1", port: port) : knownStatus
        return PortHealth(status: latency < healthyThresholdMs ? .healthy : .slow, latencyMs: latency, httpStatus: code)
    }

    /// Connect latency in ms, or nil on failure / timeout.
    private static func connect(host: String, port: UInt16) async -> Double? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let clock = ContinuousClock()
        let start = clock.now
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let gate = OnceGate()
            @Sendable func finish(_ value: Double?) {
                guard gate.fire() else { return }
                connection.cancel()
                cont.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let d = clock.now - start
                    finish(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
                case .failed, .cancelled: finish(nil)
                case .waiting: finish(nil)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
    }

    private static func headStatus(host: String, port: UInt16) async -> Int? {
        guard let url = URL(string: "http://\(host):\(port)/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await session.data(for: request) else { return nil }
        return (response as? HTTPURLResponse)?.statusCode
    }
}

/// Lets exactly one caller win; used to resume a continuation once.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
