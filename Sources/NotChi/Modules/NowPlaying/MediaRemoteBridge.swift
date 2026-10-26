// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Foundation

/// Talks to the system's now-playing service through mediaremote-adapter.
///
/// Since macOS 15.4 only Apple-entitled processes may read MediaRemote, so the adapter's
/// Perl script runs under `/usr/bin/perl` (which is entitled) and loads a small helper
/// framework that prints JSON lines. `stream` pushes a line only when something changes,
/// so there is no polling; the process sits idle in between.
final class MediaRemoteBridge: @unchecked Sendable {
    /// Called on the main queue with each update: the payload and whether it's a diff
    /// against the previous full payload (missing keys arrive as NSNull).
    var onUpdate: (@MainActor ([String: Any], _ diff: Bool) -> Void)?

    private let queue = DispatchQueue(label: "com.notchi.mediaremote")
    private var process: Process?
    private var buffer = Data()
    private var wanted = false
    private var restartDelay: TimeInterval = 1

    static let paths: (script: URL, framework: URL)? = {
        // Bundled app: Contents/Resources. `swift run`: the repo's build/ folder,
        // filled by scripts/build-mediaremote-adapter.sh.
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        roots.append(repo.appendingPathComponent("build"))
        for root in roots {
            let script = root.appendingPathComponent("mediaremote-adapter.pl")
            let framework = root.appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: script.path),
               FileManager.default.fileExists(atPath: framework.path) {
                return (script, framework)
            }
        }
        return nil
    }()

    static var isAvailable: Bool { paths != nil }

    func start() {
        queue.async {
            guard !self.wanted else { return }
            self.wanted = true
            self.restartDelay = 1
            self.launchStream()
        }
    }

    func stop() {
        queue.async {
            self.wanted = false
            self.process?.terminate()
            self.process = nil
        }
    }

    enum Command: Int {
        case togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    func send(_ command: Command) { run(["send", String(command.rawValue)]) }

    func seek(to seconds: Double) { run(["seek", String(Int64(max(0, seconds) * 1_000_000))]) }

    // MARK: - Private

    private func launchStream() {
        guard wanted, let paths = Self.paths else { return }
        let process = Process()
        // perl doesn't notice when NotChi dies (crash, force quit), so a tiny shell holds
        // our end of a pipe on stdin: when it reads EOF, NotChi is gone and it stops perl.
        // Micros: numeric timestamps instead of date strings. Debounce merges the burst of
        // small updates players send on a track change into one line.
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"/usr/bin/perl "$0" "$1" stream --micros --debounce=80 </dev/null & p=$!; trap 'kill $p' TERM; read _; kill $p"#,
                             paths.script.path, paths.framework.path]
        let lifeline = Pipe()
        process.standardInput = lifeline
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        buffer.removeAll()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.queue.async { self.consume(data) }
        }
        process.terminationHandler = { [weak self] ended in
            out.fileHandleForReading.readabilityHandler = nil
            try? lifeline.fileHandleForWriting.close()
            guard let self else { return }
            self.queue.async {
                guard self.wanted, self.process === ended else { return }
                // Crashed or killed: start again, backing off so a broken adapter
                // (a future macOS change) doesn't spin.
                let delay = self.restartDelay
                self.restartDelay = min(self.restartDelay * 2, 60)
                self.queue.asyncAfter(deadline: .now() + delay) { self.launchStream() }
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("NotChi: couldn't start media adapter: %@", error.localizedDescription)
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            restartDelay = 1
            let diff = object["diff"] as? Bool ?? false
            let handler = onUpdate
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler?(payload, diff) }
            }
        }
    }

    /// One-shot commands get their own short-lived process.
    private func run(_ arguments: [String]) {
        guard let paths = Self.paths else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
