// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import Observation
import SystemConfiguration

/// Runs the phone transfer services chosen in Settings (AirDrop watcher, Quick Share engine)
/// and turns their events into the activity the notch shows. Nothing runs for platforms
/// the user didn't pick, and with "None" nothing listens on the network at all.
@MainActor
@Observable
final class TransferCoordinator: QuickShareEngineDelegate {
    static private(set) var shared: TransferCoordinator?

    /// Ongoing and recently finished transfers, newest first. The notch shows the first.
    private(set) var activities: [TransferActivity] = []
    /// A short message such as "Received photo.jpg via AirDrop".
    private(set) var toast: String?

    var current: TransferActivity? { activities.first }
    var isActive: Bool { current != nil || toast != nil }

    @ObservationIgnored private let stash: StashStore
    @ObservationIgnored private let settings = Settings.shared
    @ObservationIgnored private let notifier = TransferNotifier()
    /// Folder the current engine writes to; a new engine is made when the setting changes.
    @ObservationIgnored private var engineFolder: URL?
    @ObservationIgnored private var watcher: DownloadsWatcher?
    @ObservationIgnored private var engine: QuickShareEngine?
    @ObservationIgnored private var speed: [UUID: (time: Date, bytes: Int64, rate: Double)] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Incoming requests answered in the notch (no notification could be shown); only these hold it open.
    @ObservationIgnored private var requestsInNotch: Set<UUID> = []

    init(stash: StashStore) {
        self.stash = stash
        Self.shared = self
        notifier.onAccept = { [weak self] id in self?.accept(id) }
        notifier.onDecline = { [weak self] id in self?.decline(id) }
        notifier.onOpen = { _ in NotchController.shared.expand(sticky: true) }
        applySettings()
    }

    func stop() {
        watcher?.stop()
        engine?.stopReceiving()
    }

    // MARK: - Sending

    var canSendToiPhone: Bool { settings.phonePlatform.usesAirDrop }
    var canSendToAndroid: Bool { settings.phonePlatform.usesQuickShare }

    func sendToiPhone(_ urls: [URL]) {
        if !AirDropSender.send(urls) { showToast("AirDrop isn't available on this Mac") }
    }

    func sendToAndroid(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let engine = ensureEngine()
        let session = engine.beginSend(files: urls)
        upsert(TransferActivity(id: session.id, channel: .quickShare, direction: .outgoing, deviceName: "Android",
                                files: urls.map { TransferFile(name: $0.lastPathComponent, size: 0) },
                                phase: .waitingForPhone(qr: session.qrURL, devices: [])))
        NotchController.shared.expand(sticky: true)
        // Sizes need disk access (possibly a folder-access prompt); keep it off the main thread.
        Task.detached(priority: .utility) { [weak self] in
            let files = urls.map { TransferFile(name: $0.lastPathComponent, size: Self.size(of: $0)) }
            await self?.update(session.id) { $0.files = files }
        }
    }

    func send(_ id: UUID, to device: QuickShareDevice) {
        engine?.send(id, to: device)
        update(id) { $0.deviceName = device.name; $0.phase = .connecting(pin: nil) }
    }

    // MARK: - User decisions

    func accept(_ id: UUID) {
        notifier.remove(id)
        engine?.respond(to: id, accept: true)
        update(id) { $0.phase = .connecting(pin: nil) }
    }

    func decline(_ id: UUID) {
        notifier.remove(id)
        engine?.respond(to: id, accept: false)
        remove(id)
    }

    func cancel(_ id: UUID) {
        notifier.remove(id)
        engine?.cancel(id)
        remove(id)
    }

    func dismiss(_ id: UUID) { remove(id) }

    // MARK: - QuickShareEngineDelegate

    func quickShareIncomingRequest(_ id: UUID, from deviceName: String, files: [TransferFile], pin: String) {
        let activity = TransferActivity(id: id, channel: .quickShare, direction: .incoming, deviceName: deviceName,
                                        files: files, phase: .incomingRequest(pin: pin))
        upsert(activity)
        // The notification carries Accept / Decline; only pop the notch open when it can't
        // be shown. The collapsed notch still flags the request ("Accept?") either way.
        notifier.notifyIncoming(id, from: deviceName, summary: activity.summary, size: activity.totalSize, pin: pin) { [weak self] shown in
            guard !shown, let self else { return }
            self.requestsInNotch.insert(id)
            self.syncHold()
            NotchController.shared.expand(sticky: true)
        }
    }

    func quickShareDevicesChanged(_ id: UUID, devices: [QuickShareDevice]) {
        update(id) { activity in
            if case .waitingForPhone(let qr, _) = activity.phase { activity.phase = .waitingForPhone(qr: qr, devices: devices) }
        }
    }

    func quickShareConnected(_ id: UUID, to deviceName: String, pin: String?) {
        update(id) { $0.deviceName = deviceName; $0.phase = .connecting(pin: pin) }
    }

    func quickShareProgress(_ id: UUID, done: Int64, total: Int64) {
        let now = Date()
        var rate = speed[id]?.rate ?? 0
        if let last = speed[id], now.timeIntervalSince(last.time) > 0.2 {
            let instant = Double(done - last.bytes) / now.timeIntervalSince(last.time)
            rate = rate == 0 ? instant : rate * 0.7 + instant * 0.3 // smooth the readout
        }
        speed[id] = (now, done, rate)
        update(id) { $0.phase = .transferring(done: done, total: total, bytesPerSecond: rate) }
    }

    func quickShareFinished(_ id: UUID, saved: [URL]) {
        speed[id] = nil
        update(id) { $0.phase = .finished(saved: saved) }
        notifier.remove(id)
        if let activity = activities.first(where: { $0.id == id }) {
            if activity.direction == .incoming {
                notifier.notifyFinished(id, title: "Received \(activity.summary)",
                                        body: "From \(activity.deviceName) · saved to \(settings.receiveFolder.lastPathComponent)")
            } else {
                notifier.notifyFinished(id, title: "Sent \(activity.summary)", body: "To \(activity.deviceName)")
            }
        }
        if !saved.isEmpty { received(saved) }
        autoDismiss(id, after: 4)
    }

    func quickShareFailed(_ id: UUID, reason: String) {
        speed[id] = nil
        notifier.remove(id)
        if let activity = activities.first(where: { $0.id == id }) {
            notifier.notifyFinished(id, title: activity.direction == .incoming ? "Couldn't receive \(activity.summary)" : "Couldn't send \(activity.summary)",
                                    body: reason)
        }
        update(id) { $0.phase = .failed(reason) }
        autoDismiss(id, after: 6)
    }

    // MARK: - Services

    private func applySettings() {
        withObservationTracking {
            let platform = settings.phonePlatform
            let visible = settings.quickShareVisible
            let folder = settings.receiveFolder
            if platform != .none { notifier.requestAuthorizationIfNeeded() }

            if platform.usesAirDrop {
                if watcher == nil {
                    let watcher = DownloadsWatcher(directory: Settings.downloadsFolder)
                    watcher.onReceived = { [weak self] urls in self?.receivedViaAirDrop(urls) }
                    watcher.start()
                    self.watcher = watcher
                }
            } else {
                watcher?.stop()
                watcher = nil
            }

            if platform.usesQuickShare {
                // A new receive folder takes effect with a fresh engine, once nothing is in flight.
                if let engine, engineFolder != folder, !activities.contains(where: { $0.channel == .quickShare }) {
                    engine.stopReceiving()
                    self.engine = nil
                }
                let engine = ensureEngine()
                if visible && !engine.isReceiving { engine.startReceiving() }
                if !visible && engine.isReceiving { engine.stopReceiving() }
            } else if let engine {
                engine.stopReceiving()
                activities.filter { $0.channel == .quickShare }.forEach { engine.cancel($0.id) }
                activities.removeAll { $0.channel == .quickShare }
                self.engine = nil
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.applySettings() }
        }
    }

    private func ensureEngine() -> QuickShareEngine {
        if let engine { return engine }
        // System Configuration answers instantly; `Host.current()` can block on DNS lookups.
        let name = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        let folder = settings.receiveFolder
        let engine = QuickShareEngine(deviceName: name, downloadsDirectory: folder)
        engine.delegate = self
        self.engine = engine
        engineFolder = folder
        return engine
    }

    /// AirDrop always lands in Downloads; move arrivals to the chosen folder if it differs.
    private func receivedViaAirDrop(_ urls: [URL]) {
        let folder = settings.receiveFolder
        guard folder.standardizedFileURL != Settings.downloadsFolder.standardizedFileURL else {
            received(urls)
            showToast("Received \(Self.describe(urls)) via AirDrop")
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let moved = urls.map { Self.move($0, into: folder) }
            await self?.received(moved)
            await self?.showToast("Received \(Self.describe(moved)) via AirDrop · moved to \(folder.lastPathComponent)")
        }
    }

    /// Moves a file into `folder` with a unique name; returns where it ended up.
    nonisolated static func move(_ url: URL, into folder: URL) -> URL {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var target = folder.appendingPathComponent(url.lastPathComponent)
        var n = 1
        while fm.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        return (try? fm.moveItem(at: url, to: target)) != nil ? target : url
    }

    private func received(_ urls: [URL]) {
        guard settings.addReceivedToStash else { return }
        urls.forEach(stash.addFile)
    }

    // MARK: - Activity bookkeeping

    private func upsert(_ activity: TransferActivity) {
        activities.removeAll { $0.id == activity.id }
        activities.insert(activity, at: 0)
        syncHold()
    }

    private func update(_ id: UUID, _ change: (inout TransferActivity) -> Void) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        var activity = activities[index]
        change(&activity)
        if activity != activities[index] { activities[index] = activity }
        syncHold()
    }

    private func remove(_ id: UUID) {
        activities.removeAll { $0.id == id }
        speed[id] = nil
        syncHold()
    }

    private func autoDismiss(_ id: UUID, after seconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.remove(id)
        }
    }

    /// Keeps the notch open while the user has to act (accept, or scan the QR code).
    private func syncHold() {
        requestsInNotch.formIntersection(activities.map(\.id))
        let needsUser = activities.contains { activity in
            switch activity.phase {
            case .incomingRequest: requestsInNotch.contains(activity.id)
            case .waitingForPhone: true
            default: false
            }
        }
        NotchState.shared.holdOpen("transfer", needsUser)
    }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Helpers

    nonisolated static func size(of url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    nonisolated static func describe(_ urls: [URL]) -> String {
        guard let first = urls.first else { return "files" }
        return urls.count == 1 ? first.lastPathComponent : "\(urls.count) files"
    }
}
