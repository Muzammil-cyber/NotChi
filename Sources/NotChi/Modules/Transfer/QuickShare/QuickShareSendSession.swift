// Adapted from NearDrop by Grishka, Unlicense.
import Foundation
import Network

/// One QR-code send: browses for Quick Share phones, auto-connects to the one that scanned our QR
/// code (or to a phone the user picks), then runs the outbound transfer. The browser only lives
/// until a connection starts, the session is cancelled, or 2 minutes pass. Queue-confined.
final class QuickShareSendSession {
    static let discoveryTimeout: TimeInterval = 120

    private struct Found {
        let endpoint: NWEndpoint
        let name: String
    }

    private let id: UUID
    private let files: [URL]
    private let qr: NearbyQRKey
    private unowned let core: QuickShareCore
    private var browser: NWBrowser?
    private var found: [String: Found] = [:]
    private var timeout: DispatchWorkItem?
    private var connection: NearbyOutbound?
    private var connecting = false
    private var finished = false

    init(id: UUID, files: [URL], qr: NearbyQRKey, core: QuickShareCore) {
        self.id = id
        self.files = files
        self.qr = qr
        self.core = core
    }

    func start() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: QuickShareCore.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            guard let self, !self.finished else { return }
            var changed = false
            for change in changes {
                switch change {
                case .added(let result), .changed(old: _, new: let result, flags: _):
                    changed = self.consider(result) || changed
                case .removed(let result):
                    if let eid = self.endpointID(of: result), self.found.removeValue(forKey: eid) != nil { changed = true }
                default: break
                }
            }
            if changed && !self.connecting { self.reportDevices() }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.finish(.failed("Can't look for phones: \(error.localizedDescription)")) }
        }
        self.browser = browser
        browser.start(queue: core.queue)

        let item = DispatchWorkItem { [weak self] in self?.finish(.failed("No phone found")) }
        timeout = item
        core.queue.asyncAfter(deadline: .now() + Self.discoveryTimeout, execute: item)
    }

    func connect(toDevice deviceID: String) {
        guard !connecting, !finished, let device = found[deviceID] else { return }
        connect(deviceID, device)
    }

    /// Silently tears the session down.
    func cancel() {
        finished = true
        stopBrowsing()
        connection?.onEnd = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: Discovery

    private func endpointID(of result: NWBrowser.Result) -> String? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }
        return QuickShareCore.endpointID(fromServiceName: name)
    }

    /// Records a discovered phone; returns true if the visible list changed. Connects when the
    /// phone's QR TLV matches ours.
    private func consider(_ result: NWBrowser.Result) -> Bool {
        guard !result.interfaces.contains(where: { $0.type == .loopback }),
              let eid = endpointID(of: result), eid != core.endpointID,
              case .bonjour(let txt) = result.metadata, let encoded = txt["n"],
              let raw = Data(urlSafeBase64: encoded), let info = NearbyEndpointInfo(data: raw) else { return false }

        var name = info.name
        let isMatch: Bool
        if let qrData = info.qrCodeData {
            if qrData == qr.advertisingToken {
                isMatch = name != nil
            } else if let hidden = qr.decryptName(qrData) {
                name = hidden
                isMatch = true
            } else {
                isMatch = false
            }
        } else {
            isMatch = false
        }
        guard let name else { return false }
        let device = Found(endpoint: result.endpoint, name: name)
        let isNew = found[eid]?.name != name
        found[eid] = device
        if isMatch && !connecting && !finished { connect(eid, device) }
        return isNew
    }

    private func reportDevices() {
        let devices = found.map { QuickShareDevice(id: $0.key, name: $0.value.name) }.sorted { $0.name < $1.name }
        core.emit(.devices(id, devices))
    }

    // MARK: Connecting

    private func connect(_ deviceID: String, _ device: Found) {
        connecting = true
        stopBrowsing()
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let nw = NWConnection(to: device.endpoint, using: NWParameters(tls: nil, tcp: tcp))
        let conn = NearbyOutbound(
            connection: nw, queue: core.queue, endpointID: core.endpointID, localName: core.deviceName, urls: files, qrKey: qr
        )
        let id = id
        conn.onConnected = { [weak self] pin in self?.core.emit(.connected(id, device.name, pin)) }
        conn.onProgress = { [weak self] done, total in self?.core.emit(.progress(id, done, total)) }
        conn.onEnd = { [weak self] outcome in self?.finish(outcome) }
        connection = conn
        conn.start()
    }

    private func stopBrowsing() {
        timeout?.cancel()
        timeout = nil
        browser?.cancel()
        browser = nil
    }

    /// Reports the outcome once and releases the session.
    private func finish(_ outcome: NearbyOutcome) {
        guard !finished else { return }
        finished = true
        stopBrowsing()
        connection?.onEnd = nil
        connection?.close()
        connection = nil
        switch outcome {
        case .finished(let saved): core.emit(.finished(id, saved))
        case .failed(let reason): core.emit(.failed(id, reason))
        }
        core.sessionEnded(id)
    }
}
