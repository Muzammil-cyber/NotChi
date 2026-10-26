// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Darwin
import Foundation

/// How a listening socket is bound.
enum PortBinding: Sendable, Equatable {
    case loopback, any, other

    var label: String {
        switch self {
        case .loopback: "localhost only"
        case .any: "all interfaces"
        case .other: "specific interface"
        }
    }
}

/// One listening TCP port, with v4/v6 duplicates of the same pid+port merged.
struct PortEntry: Identifiable, Sendable, Equatable {
    var id: String { "\(pid):\(port)" }
    let port: UInt16
    let pid: Int32
    let uid: UInt32
    let name: String
    let path: String
    let cwd: String?
    /// Short human-readable command line, e.g. "node …/vite".
    let command: String
    let hasIPv4: Bool
    let hasIPv6: Bool
    let binding: PortBinding
    /// Set when this port is published by a Docker/OrbStack container. The listening
    /// process is then the engine's port forwarder, which must never be killed.
    var container: DockerContainer? = nil

    /// True when the current user may signal this process (or stop its container).
    var isKillable: Bool { container != nil || (pid > 0 && uid == getuid()) }
}

/// Which listeners count as "dev servers" in the default (non "Show all") view.
enum PortFilter {
    /// Process names that are never dev servers (system daemons, helpers, desktop apps).
    static let excludedNames: Set<String> = [
        "rapportd", "ControlCenter", "sharingd", "identityservicesd", "launchd", "mDNSResponder",
        "AirPlayXPCHelper", "AirPlayUIAgent", "Spotify", "Spotify Helper", "Dropbox", "WhatsApp",
        "Slack", "Slack Helper", "Discord", "Notion", "Adobe Desktop Service", "AdobeIPCBroker",
        "figma_agent", "Google Chrome Helper", "Creative Cloud Helper", "ARDAgent", "screensharingd",
        "remoted", "assistantd", "apsd", "cupsd", "netbiosd", "smbd", "httpd", "sshd", "mysqld_safe",
        "logioptionsplus_agent", "OneDrive", "Raycast", "1Password", "Docker Desktop", "com.docker.backend",
    ]
    /// Executable path prefixes that mark system software.
    static let excludedPathPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/", "/Library/PrivilegedHelperTools/"]

    static func looksLikeDevServer(_ e: PortEntry) -> Bool {
        if e.container != nil { return true }
        guard e.port >= 1024 else { return false }
        if excludedNames.contains(e.name) { return false }
        if excludedPathPrefixes.contains(where: { e.path.hasPrefix($0) }) { return false }
        // GUI apps in /Applications (but not CLI tools shipped inside them) are not dev servers.
        if e.path.hasPrefix("/Applications/") && e.path.contains(".app/") && !e.path.contains("/Contents/Developer/") { return false }
        return true
    }
}

/// Enumerates listening TCP sockets through libproc, without spawning `lsof`.
enum PortScanner {
    /// Scans all processes off the main actor.
    static func scan() async -> [PortEntry] {
        await Task.detached(priority: .utility) {
            attachContainers(DockerClient.runningContainers(), to: scanSync())
        }.value
    }

    /// Labels forwarder listeners with the container that published the port. Published
    /// ports whose listener is invisible to us (e.g. a root-owned forwarder) are added
    /// as container-only entries so they still show up.
    static func attachContainers(_ containers: [DockerContainer], to entries: [PortEntry]) -> [PortEntry] {
        guard !containers.isEmpty else { return entries }
        var byPort: [UInt16: DockerContainer] = [:]
        for c in containers { for port in c.publicPorts { byPort[port] = c } }

        var result = entries
        var seen = Set<UInt16>()
        for i in result.indices {
            if let c = byPort[result[i].port] {
                result[i].container = c
                seen.insert(result[i].port)
            }
        }
        for (port, c) in byPort where !seen.contains(port) {
            result.append(PortEntry(port: port, pid: 0, uid: 0, name: c.name, path: "", cwd: nil,
                                    command: c.image, hasIPv4: true, hasIPv6: false, binding: .any, container: c))
        }
        return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    static func scanSync() -> [PortEntry] {
        var merged: [String: PortEntry] = [:]
        for pid in allPIDs() {
            for l in listeners(of: pid) {
                let key = "\(pid):\(l.port)"
                if let old = merged[key] {
                    merged[key] = PortEntry(
                        port: old.port, pid: old.pid, uid: old.uid, name: old.name, path: old.path,
                        cwd: old.cwd, command: old.command,
                        hasIPv4: old.hasIPv4 || l.v4, hasIPv6: old.hasIPv6 || l.v6,
                        binding: old.binding == .loopback ? l.binding : old.binding)
                } else {
                    let info = cachedInfo(for: pid)
                    merged[key] = PortEntry(
                        port: l.port, pid: pid, uid: info.uid, name: info.name, path: info.path,
                        cwd: info.cwd, command: info.command, hasIPv4: l.v4, hasIPv6: l.v6, binding: l.binding)
                }
            }
        }
        pruneInfoCache(keeping: Set(merged.values.map(\.pid)))
        return merged.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    // Process name/path/cwd/argv need several syscalls each; they don't change for a running
    // pid, so look them up once per listening process instead of on every 3 s rescan.
    private static let infoLock = NSLock()
    nonisolated(unsafe) private static var infoCache: [pid_t: ProcessInfoLookup] = [:]

    private static func cachedInfo(for pid: pid_t) -> ProcessInfoLookup {
        infoLock.lock(); defer { infoLock.unlock() }
        if let info = infoCache[pid] { return info }
        let info = ProcessInfoLookup(pid: pid)
        infoCache[pid] = info
        return info
    }

    private static func pruneInfoCache(keeping pids: Set<pid_t>) {
        infoLock.lock(); defer { infoLock.unlock() }
        infoCache = infoCache.filter { pids.contains($0.key) }
    }

    // MARK: - libproc

    private struct Listener { let port: UInt16; let v4: Bool; let v6: Bool; let binding: PortBinding }

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [] }
        return pids.prefix(Int(n)).filter { $0 > 0 }
    }

    private static func listeners(of pid: pid_t) -> [Listener] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 8)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard got > 0 else { return [] }

        var result: [Listener] = []
        for fd in fds.prefix(Int(got) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let r = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard r == Int32(MemoryLayout<socket_fdinfo>.size),
                  info.psi.soi_kind == Int32(SOCKINFO_TCP),
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let ini = info.psi.soi_proto.pri_tcp.tcpsi_ini
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
            let flag = Int32(ini.insi_vflag)
            let v4 = flag & INI_IPV4 != 0
            let v6 = flag & INI_IPV6 != 0
            result.append(Listener(port: port, v4: v4, v6: v6, binding: binding(of: ini, v4: v4, v6: v6)))
        }
        return result
    }

    private static func binding(of ini: in_sockinfo, v4: Bool, v6: Bool) -> PortBinding {
        if v6 && !v4 {
            let a = ini.insi_laddr.ina_6
            let words = withUnsafeBytes(of: a) { Array($0) }
            if words.allSatisfy({ $0 == 0 }) { return .any }
            if words.prefix(15).allSatisfy({ $0 == 0 }) && words[15] == 1 { return .loopback }
            return .other
        }
        let addr = UInt32(bigEndian: ini.insi_laddr.ina_46.i46a_addr4.s_addr)
        if addr == 0 { return .any }
        if addr >> 24 == 127 { return .loopback }
        // Dual-stack sockets with a v6 wildcard report a zero v4 part, handled above.
        return .other
    }

    /// Name, path, owner, cwd and command line for one pid.
    private struct ProcessInfoLookup {
        var name = "", path = "", command = ""
        var cwd: String?
        var uid: UInt32 = 0

        init(pid: pid_t) {
            var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            if proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 { path = String(cString: pathBuf) }
            var nameBuf = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 { name = String(cString: nameBuf) }
            if name.isEmpty { name = (path as NSString).lastPathComponent }
            if name.isEmpty { name = "pid \(pid)" }

            var bsd = proc_bsdinfo()
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 {
                uid = bsd.pbi_uid
            }
            var vp = proc_vnodepathinfo()
            if proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vp, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 {
                let p = withUnsafePointer(to: &vp.pvi_cdir.vip_path) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                cwd = p.isEmpty ? nil : p
            }
            command = Self.commandLine(pid: pid, fallback: name)
        }

        /// Reads argv via KERN_PROCARGS2 and shortens it to e.g. "node …/vite --port 5173".
        static func commandLine(pid: pid_t, fallback: String) -> String {
            var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
            var size = 0
            guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return fallback }
            var buf = [UInt8](repeating: 0, count: size)
            guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return fallback }
            let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
            var i = MemoryLayout<Int32>.size
            while i < size && buf[i] != 0 { i += 1 }          // exec path
            while i < size && buf[i] == 0 { i += 1 }          // padding
            var args: [String] = []
            while i < size && args.count < argc {
                var j = i
                while j < size && buf[j] != 0 { j += 1 }
                args.append(String(decoding: buf[i..<j], as: UTF8.self))
                i = j + 1
            }
            guard !args.isEmpty else { return fallback }
            let shortened = args.enumerated().map { idx, a -> String in
                guard a.hasPrefix("/") else { return a }
                let comps = a.split(separator: "/")
                return idx == 0 || comps.count <= 2 ? String(comps.last ?? "") : "…/" + (comps.last.map(String.init) ?? a)
            }
            let joined = shortened.joined(separator: " ")
            return joined.count > 80 ? String(joined.prefix(79)) + "…" : joined
        }
    }
}
