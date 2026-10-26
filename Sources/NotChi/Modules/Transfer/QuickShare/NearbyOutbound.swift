// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

// Adapted from NearDrop by Grishka, Unlicense.
import CryptoKit
import Foundation
import Network
import UniformTypeIdentifiers

/// Sender side of a Quick Share connection (we are the TCP client). Runs the handshake, sends the
/// introduction, waits for the phone to accept and streams the files.
final class NearbyOutbound: NearbyConnection {
    private enum State {
        case initial, sentClientInit, sentClientFinish, sentPairedKeyEncryption, sentPairedKeyResult
        case sentIntroduction, sending
    }

    private struct Outgoing {
        let url: URL
        let payloadID: Int64
        let size: Int64
        var offset: Int64 = 0
    }

    static let chunkSize = 512 * 1024

    /// Handshake done; the PIN is shown on both devices.
    var onConnected: ((String) -> Void)?
    var onProgress: ((Int64, Int64) -> Void)?

    private let endpointID: String
    private let localName: String
    private let urls: [URL]
    private let qrKey: NearbyQRKey?
    private var state = State.initial
    private var privateKey: P256.KeyAgreement.PrivateKey?
    private var clientInitData: Data?
    private var clientFinishData: Data?
    private var queued: [Outgoing] = []
    private var handle: FileHandle?
    private var totalBytes: Int64 = 0
    private var sentBytes: Int64 = 0
    private var cancelled = false
    /// Every chunk (and EOF marker) is out; now waiting for the phone to finish saving.
    private var allSent = false
    private var finishFallback: DispatchWorkItem?
    /// How long to wait for the phone to hang up after the last chunk before we do.
    private static let finishWait: TimeInterval = 15
    private var lastProgress = DispatchTime(uptimeNanoseconds: 0)
    private var handshakeTimeout: DispatchWorkItem?

    init(connection: NWConnection, queue: DispatchQueue, endpointID: String, localName: String, urls: [URL], qrKey: NearbyQRKey?) {
        self.endpointID = endpointID
        self.localName = localName
        self.urls = urls
        self.qrKey = qrKey
        super.init(connection: connection, queue: queue)
    }

    override var isServer: Bool { false }

    override func connectionReady() {
        let item = DispatchWorkItem { [weak self] in self?.end(.failed("Handshake timed out")) }
        handshakeTimeout = item
        queue.asyncAfter(deadline: .now() + 30, execute: item)
        do {
            try sendConnectionRequest()
            try sendClientInit()
        } catch {
            fail(error)
        }
    }

    override func peerDisconnected() {
        if allSent { end(.finished([])) } else { super.peerDisconnected() }
    }

    override func connectionLost() {
        if allSent { end(.finished([])) } else { super.connectionLost() }
    }

    override func willClose() {
        finishFallback?.cancel()
        handshakeTimeout?.cancel()
        try? handle?.close()
        handle = nil
    }

    /// Cancels from our side; tells the phone when the channel is already encrypted.
    func cancel() {
        cancelled = true
        if keys != nil {
            var frame = Sharing_Nearby_Frame()
            frame.version = .v1
            frame.v1 = Sharing_Nearby_V1Frame()
            frame.v1.type = .cancel
            try? sendSetupFrame(frame)
        }
        sendDisconnection()
        close()
    }

    // MARK: Handshake

    private func sendConnectionRequest() throws {
        var frame = Location_Nearby_Connections_OfflineFrame()
        frame.version = .v1
        frame.v1 = Location_Nearby_Connections_V1Frame()
        frame.v1.type = .connectionRequest
        frame.v1.connectionRequest = Location_Nearby_Connections_ConnectionRequestFrame()
        frame.v1.connectionRequest.endpointID = endpointID
        frame.v1.connectionRequest.endpointName = localName
        frame.v1.connectionRequest.endpointInfo = NearbyEndpointInfo(name: localName).serialize()
        frame.v1.connectionRequest.mediums = [.wifiLan]
        sendFrame(try frame.serializedBytes())
    }

    private func sendClientInit() throws {
        let key = P256.KeyAgreement.PrivateKey()
        privateKey = key

        var finish = Securegcm_Ukey2ClientFinished()
        finish.publicKey = try NearbyCrypto.genericPublicKey(for: key.publicKey).serializedBytes()
        var finishMsg = Securegcm_Ukey2Message()
        finishMsg.messageType = .clientFinish
        finishMsg.messageData = try finish.serializedBytes()
        let finishData: Data = try finishMsg.serializedBytes()
        clientFinishData = finishData

        var clientInit = Securegcm_Ukey2ClientInit()
        clientInit.version = 1
        clientInit.random = Data.random(32)
        clientInit.nextProtocol = "AES_256_CBC-HMAC_SHA256"
        var commitment = Securegcm_Ukey2ClientInit.CipherCommitment()
        commitment.commitment = Data(SHA512.hash(data: finishData))
        commitment.handshakeCipher = .p256Sha512
        clientInit.cipherCommitments.append(commitment)

        var msg = Securegcm_Ukey2Message()
        msg.messageType = .clientInit
        msg.messageData = try clientInit.serializedBytes()
        let data: Data = try msg.serializedBytes()
        clientInitData = data
        sendFrame(data)
        state = .sentClientInit
    }

    override func processFrame(_ data: Data) throws {
        switch state {
        case .sentClientInit:
            do {
                try processServerInit(try Securegcm_Ukey2Message(serializedBytes: data), raw: data)
            } catch {
                sendUkey2Alert(.badMessage)
                throw error
            }
        case .sentClientFinish:
            try processConnectionResponse(try Location_Nearby_Connections_OfflineFrame(serializedBytes: data))
        case .initial:
            throw NearbyError.protocolError("Unexpected data")
        default:
            try handleSecureMessage(try Securemessage_SecureMessage(serializedBytes: data))
        }
    }

    private func processServerInit(_ msg: Securegcm_Ukey2Message, raw: Data) throws {
        guard msg.messageType == .serverInit else { throw NearbyError.ukey2 }
        let serverInit = try Securegcm_Ukey2ServerInit(serializedBytes: msg.messageData)
        guard serverInit.version == 1, serverInit.random.count == 32, serverInit.handshakeCipher == .p256Sha512,
              let privateKey, let clientInitData, let clientFinishData else { throw NearbyError.ukey2 }
        let peer = try Securemessage_GenericPublicKey(serializedBytes: serverInit.publicKey)
        try finishKeyExchange(privateKey: privateKey, peerKey: peer, clientInit: clientInitData, serverInit: raw)
        sendFrame(clientFinishData)
        state = .sentClientFinish
        try sendConnectionResponse()
    }

    private func processConnectionResponse(_ frame: Location_Nearby_Connections_OfflineFrame) throws {
        guard frame.version == .v1, frame.v1.type == .connectionResponse else { throw NearbyError.protocolError("Unexpected frame") }
        guard frame.v1.connectionResponse.response == .accept else { throw NearbyError.protocolError("The phone refused the connection") }
        encryptionStarted()
        let signature = keys.flatMap { k in qrKey?.signature(of: k.authKey) }
        try sendSetupFrame(pairedKeyEncryptionFrame(qrSignature: signature))
        state = .sentPairedKeyEncryption
        handshakeTimeout?.cancel()
        onConnected?(keys?.pin ?? "")
    }

    // MARK: Negotiation

    override func processSetupFrame(_ frame: Sharing_Nearby_Frame) throws {
        if frame.hasV1, frame.v1.type == .cancel {
            end(.failed("The phone cancelled the transfer"))
            return
        }
        switch state {
        case .sentPairedKeyEncryption:
            guard frame.hasV1, frame.v1.hasPairedKeyEncryption else { throw NearbyError.protocolError("Expected paired key encryption") }
            try sendSetupFrame(pairedKeyResultFrame())
            state = .sentPairedKeyResult
        case .sentPairedKeyResult:
            guard frame.hasV1, frame.v1.hasPairedKeyResult else { throw NearbyError.protocolError("Expected paired key result") }
            try sendIntroduction()
        case .sentIntroduction:
            try processConsent(frame)
        default:
            break
        }
    }

    private func sendIntroduction() throws {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        frame.v1.type = .introduction
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                throw NearbyError.inputOutput("Can't send \(url.lastPathComponent)")
            }
            var meta = Sharing_Nearby_FileMetadata()
            meta.name = Self.sanitize(url.lastPathComponent)
            meta.size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            meta.mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            if meta.mimeType.hasPrefix("image/") {
                meta.type = .image
            } else if meta.mimeType.hasPrefix("video/") {
                meta.type = .video
            } else if meta.mimeType.hasPrefix("audio/") {
                meta.type = .audio
            } else if url.pathExtension.lowercased() == "apk" {
                meta.type = .androidApp
            } else {
                meta.type = .unknown
            }
            meta.payloadID = Int64.random(in: Int64.min...Int64.max)
            queued.append(Outgoing(url: url, payloadID: meta.payloadID, size: meta.size))
            frame.v1.introduction.fileMetadata.append(meta)
            totalBytes += meta.size
        }
        guard !queued.isEmpty else { throw NearbyError.inputOutput("Nothing to send") }
        try sendSetupFrame(frame)
        state = .sentIntroduction
    }

    private func processConsent(_ frame: Sharing_Nearby_Frame) throws {
        guard frame.version == .v1, frame.v1.type == .response else { throw NearbyError.protocolError("Expected response") }
        switch frame.v1.connectionResponse.status {
        case .accept:
            state = .sending
            sendNextChunk()
        case .reject, .unknown:
            declined("The phone declined the transfer")
        case .notEnoughSpace:
            declined("Not enough space on the phone")
        case .timedOut:
            declined("The phone didn't answer in time")
        case .unsupportedAttachmentType:
            declined("The phone can't receive this kind of file")
        }
    }

    private func declined(_ reason: String) {
        sendDisconnection()
        end(.failed(reason))
    }

    // MARK: Streaming

    /// Sends one chunk, then continues from the send completion so memory and queue stay bounded.
    private func sendNextChunk() {
        guard !cancelled, !isClosed else { return }
        do {
            guard var current = queued.first else {
                // Don't hang up yet: the phone still has to write the last chunk and move the
                // file into place, and an early disconnect makes it discard the file. It
                // disconnects itself once done; that (or the fallback) completes the send.
                allSent = true
                let fallback = DispatchWorkItem { [weak self] in
                    self?.sendDisconnection()
                    self?.end(.finished([]))
                }
                finishFallback = fallback
                queue.asyncAfter(deadline: .now() + Self.finishWait, execute: fallback)
                return
            }
            if handle == nil { handle = try FileHandle(forReadingFrom: current.url) }

            var transfer = Location_Nearby_Connections_PayloadTransferFrame()
            transfer.packetType = .data
            transfer.payloadHeader.id = current.payloadID
            transfer.payloadHeader.type = .file
            transfer.payloadHeader.totalSize = current.size
            transfer.payloadHeader.isSensitive = false
            transfer.payloadHeader.fileName = current.url.lastPathComponent
            transfer.payloadChunk.offset = current.offset

            if current.offset < current.size {
                let want = Int(min(Int64(Self.chunkSize), current.size - current.offset))
                guard let data = try handle?.read(upToCount: want), !data.isEmpty else {
                    throw NearbyError.inputOutput("Couldn't read \(current.url.lastPathComponent)")
                }
                transfer.payloadChunk.flags = 0
                transfer.payloadChunk.body = data
                current.offset += Int64(data.count)
                sentBytes += Int64(data.count)
                queued[0] = current
                try sendEncrypted(Self.wrap(transfer)) { [weak self] in
                    self?.reportProgress()
                    self?.sendNextChunk()
                }
            } else {
                // End-of-file marker for this payload.
                transfer.payloadChunk.flags = 1
                try? handle?.close()
                handle = nil
                queued.removeFirst()
                try sendEncrypted(Self.wrap(transfer)) { [weak self] in self?.sendNextChunk() }
            }
        } catch {
            fail(error)
        }
    }

    private func reportProgress() {
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds - lastProgress.uptimeNanoseconds >= 250_000_000 else { return }
        lastProgress = now
        onProgress?(sentBytes, totalBytes)
    }

    /// Replaces characters Android rejects in file names.
    static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "[\\/\\\\?%\\*:\\|\"<>=]", with: "_", options: .regularExpression)
    }
}
