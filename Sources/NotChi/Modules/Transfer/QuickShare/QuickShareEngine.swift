// Adapted from NearDrop by Grishka, Unlicense.
import Foundation
import Network

/// Callbacks from the Quick Share engine. Always delivered on the main actor.
@MainActor
protocol QuickShareEngineDelegate: AnyObject {
    /// An Android phone wants to send files. Answer with `QuickShareEngine.respond(to:accept:)`.
    func quickShareIncomingRequest(_ id: UUID, from deviceName: String, files: [TransferFile], pin: String)
    /// Sending: the set of visible Android phones changed (only while a send session is active).
    func quickShareDevicesChanged(_ id: UUID, devices: [QuickShareDevice])
    /// Sending: a connection to the phone is up; `pin` is shown on both devices when known.
    func quickShareConnected(_ id: UUID, to deviceName: String, pin: String?)
    /// Throttled to at most ~4 updates per second.
    func quickShareProgress(_ id: UUID, done: Int64, total: Int64)
    /// `saved` holds the received files (empty for sends).
    func quickShareFinished(_ id: UUID, saved: [URL])
    func quickShareFailed(_ id: UUID, reason: String)
}

/// Quick Share (Nearby Share) engine: receives files from Android phones by advertising over mDNS
/// and sends files to phones found through a QR code. The protocol work lives in `QuickShareCore`
/// on a private queue; this wrapper only forwards calls and delivers delegate callbacks on the
/// main actor.
@MainActor
final class QuickShareEngine {
    weak var delegate: QuickShareEngineDelegate?
    private(set) var isReceiving = false
    private let core: QuickShareCore

    /// - Parameters:
    ///   - deviceName: name Android phones show for this Mac.
    ///   - downloadsDirectory: where accepted files are written.
    init(deviceName: String, downloadsDirectory: URL) {
        core = QuickShareCore(deviceName: deviceName, downloads: downloadsDirectory)
        core.emit = { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.deliver(event) } }
        }
    }

    /// Advertise this Mac over mDNS so phones list it as a Quick Share target.
    func startReceiving() {
        isReceiving = true
        core.queue.async { [core] in core.startListening() }
    }

    func stopReceiving() {
        isReceiving = false
        core.queue.async { [core] in core.stopListening() }
    }

    func respond(to id: UUID, accept: Bool) {
        core.queue.async { [core] in core.respond(to: id, accept: accept) }
    }

    /// Starts a send session: generates a QR key, starts browsing for phones and returns the
    /// URL to encode as a QR code. A phone advertising the matching token is connected to
    /// automatically; others are reported via `quickShareDevicesChanged`.
    func beginSend(files: [URL]) -> (id: UUID, qrURL: URL) {
        let id = UUID()
        let qr = NearbyQRKey()
        core.queue.async { [core] in core.beginSend(id: id, files: files, qr: qr) }
        return (id, qr.url)
    }

    /// Sends the session's files to a phone picked from the device list.
    func send(_ id: UUID, to device: QuickShareDevice) {
        core.queue.async { [core] in core.send(id, toDevice: device.id) }
    }

    /// Cancels an incoming or outgoing transfer (and stops browsing for a send session).
    /// No delegate callback follows a cancel.
    func cancel(_ id: UUID) {
        core.queue.async { [core] in core.cancel(id) }
    }

    private func deliver(_ event: QuickShareCore.Event) {
        guard let delegate else { return }
        switch event {
        case .incoming(let id, let name, let files, let pin): delegate.quickShareIncomingRequest(id, from: name, files: files, pin: pin)
        case .devices(let id, let devices): delegate.quickShareDevicesChanged(id, devices: devices)
        case .connected(let id, let name, let pin): delegate.quickShareConnected(id, to: name, pin: pin)
        case .progress(let id, let done, let total): delegate.quickShareProgress(id, done: done, total: total)
        case .finished(let id, let saved): delegate.quickShareFinished(id, saved: saved)
        case .failed(let id, let reason): delegate.quickShareFailed(id, reason: reason)
        }
    }
}

/// Queue-confined half of the engine: the mDNS listener, inbound connections and send sessions.
/// Every method must run on `queue`.
final class QuickShareCore: @unchecked Sendable {
    enum Event {
        case incoming(UUID, String, [TransferFile], String)
        case devices(UUID, [QuickShareDevice])
        case connected(UUID, String, String?)
        case progress(UUID, Int64, Int64)
        case finished(UUID, [URL])
        case failed(UUID, String)
    }

    static let serviceType = "_FC9F5ED42C8A._tcp"
    static let maxInbound = 4

    let queue = DispatchQueue(label: "notchi.quickshare", qos: .utility)
    let deviceName: String
    let downloads: URL
    /// 4 random alphanumeric characters identifying this Mac to phones.
    let endpointID: String
    var emit: (@Sendable (Event) -> Void) = { _ in }

    private let endpointInfo: Data
    private var listener: NWListener?
    private var listenerRetries = 0
    private var inbound: [UUID: NearbyInbound] = [:]
    private var sessions: [UUID: QuickShareSendSession] = [:]

    init(deviceName: String, downloads: URL) {
        self.deviceName = deviceName
        self.downloads = downloads
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        endpointID = String((0..<4).map { _ in alphabet.randomElement()! })
        endpointInfo = NearbyEndpointInfo(name: deviceName).serialize()
    }

    /// mDNS instance name: PCP byte, endpoint ID, service ID hash and two zero bytes, URL-safe base64.
    static func serviceName(endpointID: String) -> String {
        (Data([0x23]) + Data(endpointID.utf8) + Data([0xFC, 0x9F, 0x5E, 0, 0])).urlSafeBase64()
    }

    /// Endpoint ID encoded in a discovered service name, if it is a Quick Share one.
    static func endpointID(fromServiceName name: String) -> String? {
        guard let d = Data(urlSafeBase64: name), d.count >= 10, d[0] == 0x23, Array(d[5..<8]) == [0xFC, 0x9F, 0x5E] else { return nil }
        return String(data: d[1..<5], encoding: .ascii)
    }

    // MARK: Receiving

    func startListening() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(
                name: Self.serviceName(endpointID: endpointID), type: Self.serviceType,
                txtRecord: NWTXTRecord(["n": endpointInfo.urlSafeBase64()])
            )
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, let l, self.listener === l else { return }
                switch state {
                case .ready: self.listenerRetries = 0
                case .failed: self.listenerFailed()
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener = l
            l.start(queue: queue)
        } catch {
            listenerFailed()
        }
    }

    func stopListening() {
        listener?.cancel()
        listener = nil
        listenerRetries = 0
    }

    /// Retries a few times with a delay (a one-shot, not a poll).
    private func listenerFailed() {
        listener?.cancel()
        listener = nil
        guard listenerRetries < 3 else { return }
        listenerRetries += 1
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.listener == nil, self.listenerRetries > 0 else { return }
            self.startListening()
        }
    }

    private func accept(_ nw: NWConnection) {
        guard inbound.count < Self.maxInbound else {
            nw.cancel()
            return
        }
        let conn = NearbyInbound(connection: nw, queue: queue, downloads: downloads)
        let id = conn.id
        inbound[id] = conn
        conn.onRequest = { [weak self] name, files, pin in self?.emit(.incoming(id, name, files, pin)) }
        conn.onProgress = { [weak self] done, total in self?.emit(.progress(id, done, total)) }
        conn.onEnd = { [weak self, weak conn] outcome in
            guard let self else { return }
            self.inbound[id] = nil
            guard conn?.requestReported == true else { return }
            switch outcome {
            case .finished(let saved): self.emit(.finished(id, saved))
            case .failed(let reason): self.emit(.failed(id, reason))
            }
        }
        conn.start()
    }

    func respond(to id: UUID, accept: Bool) {
        inbound[id]?.decide(accept: accept)
    }

    // MARK: Sending

    func beginSend(id: UUID, files: [URL], qr: NearbyQRKey) {
        let session = QuickShareSendSession(id: id, files: files, qr: qr, core: self)
        sessions[id] = session
        session.start()
    }

    func send(_ id: UUID, toDevice deviceID: String) {
        sessions[id]?.connect(toDevice: deviceID)
    }

    func sessionEnded(_ id: UUID) {
        sessions[id] = nil
    }

    func cancel(_ id: UUID) {
        if let session = sessions.removeValue(forKey: id) {
            session.cancel()
        } else if let conn = inbound.removeValue(forKey: id) {
            conn.onEnd = nil
            conn.close()
        }
    }
}
