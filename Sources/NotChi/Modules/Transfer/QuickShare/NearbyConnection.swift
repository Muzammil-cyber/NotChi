// Adapted from NearDrop by Grishka, Unlicense.
import CryptoKit
import Foundation
import Network

/// How a connection ended. Reported exactly once.
enum NearbyOutcome {
    case finished([URL])
    case failed(String)
}

/// One Quick Share TCP connection: length-prefixed framing, SecureMessage encryption, payload
/// reassembly and keep-alives. Subclasses implement the inbound (receiver) and outbound (sender)
/// state machines. Everything runs on the single engine queue.
class NearbyConnection {
    static let maxFrameLength = 5 * 1024 * 1024
    static let keepAliveInterval: TimeInterval = 10

    let connection: NWConnection
    let queue: DispatchQueue
    var onEnd: ((NearbyOutcome) -> Void)?

    private(set) var keys: NearbyCrypto.SessionKeys?
    private(set) var isClosed = false
    private var ended = false
    private var sendSequence: Int32 = 0
    private var receiveSequence: Int32 = 0
    private var payloadBuffers: [Int64: Data] = [:]
    private var keepAliveTimer: DispatchSourceTimer?

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    // MARK: Subclass hooks

    var isServer: Bool { fatalError("override") }
    /// TCP is up (called once).
    func connectionReady() {}
    /// A raw frame arrived (handshake phase or SecureMessage).
    func processFrame(_ data: Data) throws { fatalError("override") }
    /// A decoded Nearby Share frame arrived over the encrypted channel.
    func processSetupFrame(_ frame: Sharing_Nearby_Frame) throws {}
    /// A chunk of a FILE payload arrived.
    func processFileChunk(_ transfer: Location_Nearby_Connections_PayloadTransferFrame) throws {
        throw NearbyError.protocolError("Unexpected file payload")
    }
    /// A complete BYTES payload arrived; return true when handled (otherwise it is parsed as a setup frame).
    func processBytesPayload(_ data: Data, id: Int64) throws -> Bool { false }
    /// The peer sent a disconnection frame.
    func peerDisconnected() { end(.failed("The other device disconnected")) }

    /// The socket closed or errored. Subclasses may treat this as success (e.g. the
    /// receiver hanging up after saving everything we sent).
    func connectionLost() { end(.failed("Connection lost")) }

    // MARK: Lifecycle

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isClosed else { return }
            switch state {
            case .ready:
                self.connectionReady()
                self.receiveHeader()
            case .failed(let error):
                self.end(.failed("Connection failed: \(error.localizedDescription)"))
            case .cancelled:
                self.connectionLost()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    /// Reports the outcome (first call wins) and closes the socket.
    func end(_ outcome: NearbyOutcome) {
        if !ended {
            ended = true
            onEnd?(outcome)
        }
        close()
    }


    func close() {
        guard !isClosed else { return }
        isClosed = true
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        connection.stateUpdateHandler = nil
        let conn = connection
        conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
        // Safety net if the peer never lets the FIN drain.
        queue.asyncAfter(deadline: .now() + 5) { conn.cancel() }
        willClose()
    }

    func willClose() {}

    func fail(_ error: Error) {
        end(.failed(String(describing: error)))
    }

    // MARK: Framing

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, !self.isClosed else { return }
            guard error == nil, let data, data.count == 4 else {
                self.connectionLost()
                return
            }
            let b = [UInt8](data)
            let length = Int(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
            guard length > 0, length < Self.maxFrameLength else {
                self.end(.failed("Unexpected packet length"))
                return
            }
            self.receiveBody(length)
        }
    }

    private func receiveBody(_ length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self, !self.isClosed else { return }
            guard error == nil, let data, data.count == length else {
                self.connectionLost()
                return
            }
            do {
                try self.processFrame(data)
            } catch {
                self.fail(error)
                return
            }
            if !self.isClosed { self.receiveHeader() }
        }
    }

    func sendFrame(_ frame: Data, completion: (() -> Void)? = nil) {
        guard !isClosed else { return }
        let n = frame.count
        var out = Data([UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)])
        out.append(frame)
        connection.send(content: out, completion: .contentProcessed { error in
            if error == nil { completion?() }
        })
    }

    // MARK: Key exchange

    func finishKeyExchange(privateKey: P256.KeyAgreement.PrivateKey, peerKey: Securemessage_GenericPublicKey, clientInit: Data, serverInit: Data) throws {
        keys = try NearbyCrypto.deriveKeys(
            privateKey: privateKey, peerKey: NearbyCrypto.publicKey(from: peerKey),
            clientInit: clientInit, serverInit: serverInit, isServer: isServer
        )
    }

    /// Call once the plaintext connection responses were exchanged.
    func encryptionStarted() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.keepAliveInterval, repeating: Self.keepAliveInterval)
        timer.setEventHandler { [weak self] in self?.sendKeepAlive(ack: false) }
        timer.resume()
        keepAliveTimer = timer
    }

    // MARK: Encrypted channel

    func sendEncrypted(_ frame: Location_Nearby_Connections_OfflineFrame, completion: (() -> Void)? = nil) throws {
        guard let keys else { throw NearbyError.protocolError("Keys not ready") }
        var d2d = Securegcm_DeviceToDeviceMessage()
        sendSequence += 1
        d2d.sequenceNumber = sendSequence
        d2d.message = try frame.serializedBytes()

        let iv = Data.random(16)
        var hb = Securemessage_HeaderAndBody()
        hb.body = try NearbyCrypto.aesCBC(encrypt: true, key: keys.encryptKey, iv: iv, input: try d2d.serializedBytes())
        hb.header = Securemessage_Header()
        hb.header.encryptionScheme = .aes256Cbc
        hb.header.signatureScheme = .hmacSha256
        hb.header.iv = iv
        var meta = Securegcm_GcmMetadata()
        meta.type = .deviceToDeviceMessage
        meta.version = 1
        hb.header.publicMetadata = try meta.serializedBytes()

        var msg = Securemessage_SecureMessage()
        msg.headerAndBody = try hb.serializedBytes()
        msg.signature = Data(HMAC<SHA256>.authenticationCode(for: msg.headerAndBody, using: keys.sendHmacKey))
        sendFrame(try msg.serializedBytes(), completion: completion)
    }

    func sendSetupFrame(_ frame: Sharing_Nearby_Frame) throws {
        try sendBytesPayload(try frame.serializedBytes(), id: Int64.random(in: Int64.min...Int64.max))
    }

    /// Android sends each negotiation message as a data chunk followed by an empty LAST_CHUNK; do the same.
    func sendBytesPayload(_ data: Data, id: Int64) throws {
        var transfer = Location_Nearby_Connections_PayloadTransferFrame()
        transfer.packetType = .data
        transfer.payloadChunk.offset = 0
        transfer.payloadChunk.flags = 0
        transfer.payloadChunk.body = data
        transfer.payloadHeader.id = id
        transfer.payloadHeader.type = .bytes
        transfer.payloadHeader.totalSize = Int64(data.count)
        transfer.payloadHeader.isSensitive = false
        try sendEncrypted(Self.wrap(transfer))

        transfer.payloadChunk.flags = 1
        transfer.payloadChunk.offset = Int64(data.count)
        transfer.payloadChunk.clearBody()
        try sendEncrypted(Self.wrap(transfer))
    }

    static func wrap(_ transfer: Location_Nearby_Connections_PayloadTransferFrame) -> Location_Nearby_Connections_OfflineFrame {
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1 = Location_Nearby_Connections_V1Frame()
        frame.v1.type = .payloadTransfer
        frame.v1.payloadTransfer = transfer
        return frame
    }

    func handleSecureMessage(_ msg: Securemessage_SecureMessage) throws {
        guard let keys, msg.hasSignature, msg.hasHeaderAndBody else { throw NearbyError.protocolError("Malformed secure message") }
        guard HMAC<SHA256>.isValidAuthenticationCode(msg.signature, authenticating: msg.headerAndBody, using: keys.recvHmacKey) else {
            throw NearbyError.protocolError("Bad message signature")
        }
        let hb = try Securemessage_HeaderAndBody(serializedBytes: msg.headerAndBody)
        let plain = try NearbyCrypto.aesCBC(encrypt: false, key: keys.decryptKey, iv: hb.header.iv, input: hb.body)
        let d2d = try Securegcm_DeviceToDeviceMessage(serializedBytes: plain)
        guard d2d.hasMessage, d2d.hasSequenceNumber else { throw NearbyError.protocolError("Malformed device message") }
        receiveSequence += 1
        guard d2d.sequenceNumber == receiveSequence else { throw NearbyError.protocolError("Wrong sequence number") }

        let frame = try Location_Nearby_Connections_OfflineFrame(serializedBytes: d2d.message)
        guard frame.hasV1, frame.v1.hasType else { return }
        switch frame.v1.type {
        case .payloadTransfer:
            try handlePayloadTransfer(frame.v1.payloadTransfer)
        case .keepAlive:
            if !frame.v1.keepAlive.ack { sendKeepAlive(ack: true) }
        case .disconnection:
            peerDisconnected()
        case .bandwidthUpgradeNegotiation:
            handleBandwidthUpgrade(frame.v1.bandwidthUpgradeNegotiation)
        case .bandwidthUpgradeRetry:
            handleBandwidthUpgradeRetry(frame.v1.bandwidthUpgradeRetry)
        default:
            break
        }
    }

    /// Newer phones ask which mediums we could retry an upgrade on and wait for the answer.
    /// We only do Wi-Fi LAN, which is the socket already in use, so say exactly that.
    private func handleBandwidthUpgradeRetry(_ retry: Location_Nearby_Connections_BandwidthUpgradeRetryFrame) {
        guard retry.isRequest else { return }
        var reply = Location_Nearby_Connections_OfflineFrame()
        reply.version = .v1
        reply.v1.type = .bandwidthUpgradeRetry
        reply.v1.bandwidthUpgradeRetry.supportedMedium = [.wifiLan]
        reply.v1.bandwidthUpgradeRetry.isRequest = false
        try? sendEncrypted(reply)
    }

    /// Phones offer to move the transfer to a faster medium (Wi-Fi Direct, hotspot, ...).
    /// macOS can't join those, so decline and the phone keeps using this Wi-Fi LAN socket.
    private func handleBandwidthUpgrade(_ upgrade: Location_Nearby_Connections_BandwidthUpgradeNegotiationFrame) {
        guard upgrade.eventType == .upgradePathAvailable else { return }
        var reply = Location_Nearby_Connections_OfflineFrame()
        reply.version = .v1
        reply.v1.type = .bandwidthUpgradeNegotiation
        reply.v1.bandwidthUpgradeNegotiation.eventType = .upgradeFailure
        reply.v1.bandwidthUpgradeNegotiation.upgradePathInfo = upgrade.upgradePathInfo
        try? sendEncrypted(reply)
    }

    private func handlePayloadTransfer(_ transfer: Location_Nearby_Connections_PayloadTransferFrame) throws {
        let header = transfer.payloadHeader
        let chunk = transfer.payloadChunk
        guard transfer.hasPayloadHeader, transfer.hasPayloadChunk, header.hasType, header.hasID, chunk.hasOffset, chunk.hasFlags else {
            throw NearbyError.protocolError("Malformed payload transfer")
        }
        if transfer.packetType == .control {
            // Acks / cancels about a payload, not payload data.
            return
        }
        switch header.type {
        case .bytes:
            let id = header.id
            guard header.totalSize <= Int64(Self.maxFrameLength) else { throw NearbyError.protocolError("Payload too large") }
            var buffer = payloadBuffers[id] ?? Data()
            guard chunk.offset == Int64(buffer.count) else { throw NearbyError.protocolError("Unexpected chunk offset") }
            if chunk.hasBody { buffer.append(chunk.body) }
            guard buffer.count <= Self.maxFrameLength else { throw NearbyError.protocolError("Payload too large") }
            if chunk.flags & 1 == 1 {
                payloadBuffers[id] = nil
                if !(try processBytesPayload(buffer, id: id)) {
                    try processSetupFrame(try Sharing_Nearby_Frame(serializedBytes: buffer))
                }
            } else {
                payloadBuffers[id] = buffer
            }
        case .file:
            try processFileChunk(transfer)
        default:
            break
        }
    }

    func sendKeepAlive(ack: Bool) {
        guard keys != nil else { return }
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1.type = .keepAlive
        frame.v1.keepAlive.ack = ack
        try? sendEncrypted(frame)
    }

    func sendDisconnection() {
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1.type = .disconnection
        frame.v1.disconnection = Location_Nearby_Connections_DisconnectionFrame()
        if keys != nil {
            try? sendEncrypted(frame)
        } else if let data: Data = try? frame.serializedBytes() {
            sendFrame(data)
        }
    }

    func sendUkey2Alert(_ type: Securegcm_Ukey2Alert.AlertType) {
        var alert = Securegcm_Ukey2Alert()
        alert.type = type
        var msg = Securegcm_Ukey2Message()
        msg.messageType = .alert
        if let alertData: Data = try? alert.serializedBytes() { msg.messageData = alertData }
        if let data: Data = try? msg.serializedBytes() { sendFrame(data) }
    }

    func sendConnectionResponse() throws {
        var resp = Location_Nearby_Connections_OfflineFrame()
        resp.version = .v1
        resp.v1 = Location_Nearby_Connections_V1Frame()
        resp.v1.type = .connectionResponse
        resp.v1.connectionResponse = Location_Nearby_Connections_ConnectionResponseFrame()
        resp.v1.connectionResponse.response = .accept
        resp.v1.connectionResponse.status = 0
        resp.v1.connectionResponse.osInfo = Location_Nearby_Connections_OsInfo()
        resp.v1.connectionResponse.osInfo.type = .apple
        sendFrame(try resp.serializedBytes())
    }

    func pairedKeyEncryptionFrame(qrSignature: Data? = nil) -> Sharing_Nearby_Frame {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        frame.v1 = Sharing_Nearby_V1Frame()
        frame.v1.type = .pairedKeyEncryption
        frame.v1.pairedKeyEncryption = Sharing_Nearby_PairedKeyEncryptionFrame()
        // We cannot talk to Google's servers, so these are filler like in NearDrop.
        frame.v1.pairedKeyEncryption.secretIDHash = Data.random(6)
        frame.v1.pairedKeyEncryption.signedData = Data.random(72)
        if let qrSignature { frame.v1.pairedKeyEncryption.qrCodeHandshakeData = qrSignature }
        return frame
    }

    func pairedKeyResultFrame() -> Sharing_Nearby_Frame {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        frame.v1 = Sharing_Nearby_V1Frame()
        frame.v1.type = .pairedKeyResult
        frame.v1.pairedKeyResult = Sharing_Nearby_PairedKeyResultFrame()
        frame.v1.pairedKeyResult.status = .unable
        return frame
    }
}
