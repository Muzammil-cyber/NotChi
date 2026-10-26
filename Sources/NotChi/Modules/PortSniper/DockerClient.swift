// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Darwin
import Foundation

/// A running container that publishes at least one TCP port on the host.
struct DockerContainer: Sendable, Equatable {
    let id: String
    let name: String
    let image: String
    /// Host ports published over TCP.
    let publicPorts: Set<UInt16>
}

/// Minimal Docker Engine API client over the local unix socket. Works with
/// Docker Desktop, OrbStack, Colima and Rancher Desktop. Calls block, so run them
/// off the main actor.
enum DockerClient {
    /// Candidate engine sockets, in priority order. `DOCKER_HOST` wins when it names a unix socket.
    static var socketPaths: [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        if let host = ProcessInfo.processInfo.environment["DOCKER_HOST"], host.hasPrefix("unix://") {
            paths.append(String(host.dropFirst("unix://".count)))
        }
        paths += [
            "\(home)/.orbstack/run/docker.sock",
            "\(home)/.docker/run/docker.sock",
            "\(home)/.colima/default/docker.sock",
            "\(home)/.rd/docker.sock",
            "/var/run/docker.sock",
        ]
        return paths
    }

    /// Running containers with published TCP ports; empty when no engine is reachable.
    static func runningContainers() -> [DockerContainer] {
        guard let (status, body) = request("GET", "/containers/json"), status == 200,
              let list = try? JSONDecoder().decode([ContainerJSON].self, from: body) else { return [] }
        return list.compactMap { c in
            let ports = Set((c.Ports ?? []).compactMap { p -> UInt16? in
                guard p.type == "tcp", let pub = p.PublicPort else { return nil }
                return UInt16(exactly: pub)
            })
            guard !ports.isEmpty else { return nil }
            let name = c.Names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(c.Id.prefix(12))
            return DockerContainer(id: c.Id, name: name, image: c.Image, publicPorts: ports)
        }
    }

    /// Stops a container gracefully (SIGTERM, then SIGKILL after `timeout` seconds, done by the engine).
    static func stop(id: String, timeout: Int = 5) -> Bool {
        guard let (status, _) = request("POST", "/containers/\(id)/stop?t=\(timeout)", readTimeout: timeout + 10) else { return false }
        return status == 204 || status == 304 // 304: already stopped
    }

    // MARK: - HTTP over a unix socket

    private struct ContainerJSON: Decodable {
        let Id: String
        let Names: [String]
        let Image: String
        let Ports: [PortJSON]?
    }

    private struct PortJSON: Decodable {
        let PublicPort: Int?
        let type: String

        enum CodingKeys: String, CodingKey { case PublicPort, type = "Type" }
    }

    /// Sends an HTTP/1.0 request so the engine closes the connection when done. Some engines
    /// (OrbStack) still use chunked encoding, so the body is de-chunked when needed.
    private static func request(_ method: String, _ path: String, readTimeout: Int = 2) -> (Int, Data)? {
        for socketPath in socketPaths where FileManager.default.fileExists(atPath: socketPath) {
            if let result = request(method, path, socketPath: socketPath, readTimeout: readTimeout) { return result }
        }
        return nil
    }

    private static func request(_ method: String, _ path: String, socketPath: String, readTimeout: Int) -> (Int, Data)? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: readTimeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes)
            buf[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let head = "\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\n\r\n"
        let sent = head.withCString { send(fd, $0, strlen($0), 0) }
        guard sent > 0 else { return nil }

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        // Engines may keep the connection open, so stop as soon as the response is complete
        // instead of waiting for EOF (which would cost the full read timeout).
        while !isComplete(response) {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            response.append(chunk, count: n)
        }

        guard let split = response.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: response[..<split.lowerBound], encoding: .utf8),
              let statusLine = head.split(separator: "\r\n").first,
              let status = statusLine.split(separator: " ").dropFirst().first.flatMap({ Int($0) })
        else { return nil }
        let body = Data(response[split.upperBound...])
        let chunked = head.lowercased().contains("transfer-encoding: chunked")
        return (status, chunked ? dechunk(body) : body)
    }

    /// True once the headers plus a full chunked or Content-Length body have arrived.
    private static func isComplete(_ response: Data) -> Bool {
        guard let split = response.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(decoding: response[..<split.lowerBound], as: UTF8.self).lowercased()
        let bodyCount = response.distance(from: split.upperBound, to: response.endIndex)
        if head.contains("transfer-encoding: chunked") {
            return response.suffix(5).elementsEqual("0\r\n\r\n".utf8)
        }
        if let line = head.split(separator: "\r\n").first(where: { $0.hasPrefix("content-length:") }),
           let length = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) {
            return bodyCount >= length
        }
        // No length information (e.g. 204 No Content): done unless a body might follow until EOF.
        return head.hasPrefix("http/1.1 204") || head.hasPrefix("http/1.0 204") || head.hasPrefix("http/1.1 304")
    }

    private static func dechunk(_ data: Data) -> Data {
        var out = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while let lineEnd = data.range(of: crlf, in: index..<data.endIndex) {
            let sizeField = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
                .split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeField.trimmingCharacters(in: .whitespaces), radix: 16), size > 0 else { break }
            let start = lineEnd.upperBound
            let end = min(start + size, data.endIndex)
            out.append(data[start..<end])
            index = min(end + crlf.count, data.endIndex)
        }
        return out
    }
}
