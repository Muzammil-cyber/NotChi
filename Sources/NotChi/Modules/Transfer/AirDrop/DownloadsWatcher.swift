import Darwin
import Foundation

/// Notices files that AirDrop drops into ~/Downloads.
///
/// Event-driven: a kqueue vnode source fires only when the folder changes, so it costs
/// nothing while idle. AirDrop files are recognised by their quarantine attribute, which
/// names `sharingd` (the AirDrop daemon) as the agent; browser downloads are ignored.
@MainActor
final class DownloadsWatcher {
    var onReceived: (([URL]) -> Void)?

    private let directory: URL
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var pending: Task<Void, Never>?
    private var starting = false

    init(directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.directory = directory
    }

    func start() {
        guard source == nil, !starting else { return }
        starting = true
        let path = directory.path
        // The first touch of ~/Downloads can show a privacy prompt, and macOS blocks the
        // calling thread until the user answers; keep that off the main thread.
        Task.detached(priority: .utility) { [weak self] in
            let fd = open(path, O_EVTONLY)
            let error = errno
            let names = fd >= 0 ? ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []) : []
            if let self {
                await self.finishStart(fd: fd, error: error, names: names)
            } else if fd >= 0 {
                close(fd)
            }
        }
    }

    private func finishStart(fd: Int32, error: Int32, names: [String]) {
        // Stopped while waiting on the prompt: discard.
        guard starting else { if fd >= 0 { close(fd) }; return }
        starting = false
        guard fd >= 0 else {
            NSLog("NotChi: can't watch %@ (errno %d)", directory.path, error)
            return
        }
        attach(fd: fd, initial: names)
    }

    private func attach(fd: Int32, initial: [String]) {
        known = Set(initial)
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        starting = false
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    // MARK: - Internals

    private func folderChanged() {
        // Coalesce bursts (AirDrop writes, renames, then sets attributes).
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.scan()
        }
    }

    private func scan() async {
        let directory = directory, previous = known
        // Listing, attribute reads and the stability wait all hit the disk: do them off-main.
        let (current, stable) = await Task.detached(priority: .utility) { () -> (Set<String>, [URL]) in
            let current = Set(Self.listing(of: directory))
            let candidates = current.subtracting(previous)
                .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".download") && !$0.hasSuffix(".part") && !$0.hasSuffix(".crdownload") }
                .map { directory.appendingPathComponent($0) }
                .filter(Self.isFromAirDrop)
            guard !candidates.isEmpty else { return (current, []) }
            // Wait until sizes stop changing so a half-written file isn't reported.
            return (current, await Self.waitUntilStable(candidates))
        }.value
        known = current
        if !stable.isEmpty { onReceived?(stable) }
    }

    nonisolated private static func listing(of directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    nonisolated static func isFromAirDrop(_ url: URL) -> Bool {
        let name = "com.apple.quarantine"
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path, name, &buffer, length, 0, 0) == length else { return false }
        // Format: flags;timestamp;agent;uuid
        let fields = String(decoding: buffer, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
        return fields.count > 2 && fields[2].localizedCaseInsensitiveContains("sharingd")
    }

    nonisolated private static func waitUntilStable(_ urls: [URL]) async -> [URL] {
        func sizes() -> [URL: Int64] {
            Dictionary(uniqueKeysWithValues: urls.compactMap { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64).map { (url, $0) }
            })
        }
        var previous = sizes()
        for _ in 0..<30 {
            try? await Task.sleep(for: .seconds(1))
            let now = sizes()
            if now == previous { return urls.filter { now[$0] != nil } }
            previous = now
        }
        return urls.filter { previous[$0] != nil }
    }
}
