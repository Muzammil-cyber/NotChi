// Adapted from NearDrop by Grishka, Unlicense.
import CryptoKit
import Foundation
import Network

/// Receiver side of a Quick Share connection (we are the TCP server). Runs the handshake, asks the
/// owner for consent once the sender's introduction arrives, then writes files to disk.
final class NearbyInbound: NearbyConnection {
    private enum State {
        case initial, gotConnectionRequest, sentServerInit, gotClientFinish, sentConnectionResponse
        case sentPairedKeyResult, gotPairedKeyResult, waitingForConsent, receiving
    }

    /// One incoming payload: a file or an inline text/URL.
    private struct Incoming {
        let payloadID: Int64
        let name: String
        var size: Int64
        let isText: Bool
        var finalURL: URL?
        var partURL: URL?
        var handle: FileHandle?
        var received: Int64 = 0
    }

    let id = UUID()
    /// Sender name, files and PIN once the introduction was parsed.
    var onRequest: ((String, [TransferFile], String) -> Void)?
    var onProgress: ((Int64, Int64) -> Void)?

    private let downloads: URL
    private var state = State.initial
    private var senderName = "Unknown device"
    private var cipherCommitment: Data?
    private var privateKey: P256.KeyAgreement.PrivateKey?
    private var clientInitData: Data?
    private var serverInitData: Data?
    private var items: [Incoming] = []
    private var saved: [URL] = []
    private var totalBytes: Int64 = 0
    private var receivedBytes: Int64 = 0
    private var lastProgress = DispatchTime(uptimeNanoseconds: 0)
    private var handshakeTimeout: DispatchWorkItem?

    /// True once the owner was asked, so failures need to be reported to them.
    private(set) var requestReported = false

    init(connection: NWConnection, queue: DispatchQueue, downloads: URL) {
        self.downloads = downloads
        super.init(connection: connection, queue: queue)
    }

    override var isServer: Bool { true }


    override func connectionReady() {
        // Drop peers that stall the handshake.
        let item = DispatchWorkItem { [weak self] in self?.end(.failed("Handshake timed out")) }
        handshakeTimeout = item
        queue.asyncAfter(deadline: .now() + 30, execute: item)
    }

    override func willClose() {
        handshakeTimeout?.cancel()
        for item in items {
            try? item.handle?.close()
            if let part = item.partURL { try? FileManager.default.removeItem(at: part) }
        }
        items.removeAll()
    }

    // MARK: Handshake

    override func processFrame(_ data: Data) throws {
        switch state {
        case .initial:
            try processConnectionRequest(try Location_Nearby_Connections_OfflineFrame(serializedBytes: data))
        case .gotConnectionRequest:
            clientInitData = data
            try processClientInit(try Securegcm_Ukey2Message(serializedBytes: data))
        case .sentServerInit:
            try processClientFinish(try Securegcm_Ukey2Message(serializedBytes: data), raw: data)
        case .gotClientFinish:
            try processConnectionResponse(try Location_Nearby_Connections_OfflineFrame(serializedBytes: data))
        default:
            try handleSecureMessage(try Securemessage_SecureMessage(serializedBytes: data))
        }
    }

    private func processConnectionRequest(_ frame: Location_Nearby_Connections_OfflineFrame) throws {
        guard frame.hasV1, frame.v1.type == .connectionRequest, frame.v1.hasConnectionRequest,
              frame.v1.connectionRequest.hasEndpointInfo else { throw NearbyError.protocolError("Bad connection request") }
        senderName = NearbyEndpointInfo(data: frame.v1.connectionRequest.endpointInfo)?.name
            ?? (frame.v1.connectionRequest.hasEndpointName ? frame.v1.connectionRequest.endpointName : senderName)
        state = .gotConnectionRequest
    }

    private func processClientInit(_ msg: Securegcm_Ukey2Message) throws {
        guard msg.hasMessageType, msg.hasMessageData, msg.messageType == .clientInit else {
            sendUkey2Alert(.badMessageType)
            throw NearbyError.ukey2
        }
        guard let clientInit = try? Securegcm_Ukey2ClientInit(serializedBytes: msg.messageData) else {
            sendUkey2Alert(.badMessageData)
            throw NearbyError.ukey2
        }
        guard clientInit.version == 1 else { sendUkey2Alert(.badVersion); throw NearbyError.ukey2 }
        guard clientInit.random.count == 32 else { sendUkey2Alert(.badRandom); throw NearbyError.ukey2 }
        guard let commitment = clientInit.cipherCommitments.first(where: { $0.handshakeCipher == .p256Sha512 }) else {
            sendUkey2Alert(.badHandshakeCipher)
            throw NearbyError.ukey2
        }
        cipherCommitment = commitment.commitment
        guard clientInit.nextProtocol == "AES_256_CBC-HMAC_SHA256" else { sendUkey2Alert(.badNextProtocol); throw NearbyError.ukey2 }

        let key = P256.KeyAgreement.PrivateKey()
        privateKey = key
        var serverInit = Securegcm_Ukey2ServerInit()
        serverInit.version = 1
        serverInit.random = Data.random(32)
        serverInit.handshakeCipher = .p256Sha512
        serverInit.publicKey = try NearbyCrypto.genericPublicKey(for: key.publicKey).serializedBytes()

        var out = Securegcm_Ukey2Message()
        out.messageType = .serverInit
        out.messageData = try serverInit.serializedBytes()
        let data: Data = try out.serializedBytes()
        serverInitData = data
        sendFrame(data)
        state = .sentServerInit
    }

    private func processClientFinish(_ msg: Securegcm_Ukey2Message, raw: Data) throws {
        guard msg.hasMessageType, msg.hasMessageData, msg.messageType == .clientFinish,
              let privateKey, let clientInitData, let serverInitData else { throw NearbyError.ukey2 }
        guard cipherCommitment == Data(SHA512.hash(data: raw)) else { throw NearbyError.ukey2 }
        let finish = try Securegcm_Ukey2ClientFinished(serializedBytes: msg.messageData)
        guard finish.hasPublicKey else { throw NearbyError.ukey2 }
        let peer = try Securemessage_GenericPublicKey(serializedBytes: finish.publicKey)
        try finishKeyExchange(privateKey: privateKey, peerKey: peer, clientInit: clientInitData, serverInit: serverInitData)
        state = .gotClientFinish
    }

    private func processConnectionResponse(_ frame: Location_Nearby_Connections_OfflineFrame) throws {
        guard frame.hasV1, frame.v1.type == .connectionResponse else { return }
        try sendConnectionResponse()
        encryptionStarted()
        try sendSetupFrame(pairedKeyEncryptionFrame())
        state = .sentConnectionResponse
    }

    override func processSetupFrame(_ frame: Sharing_Nearby_Frame) throws {
        if frame.hasV1, frame.v1.type == .cancel {
            end(.failed("The sender cancelled the transfer"))
            return
        }
        switch state {
        case .sentConnectionResponse:
            guard frame.hasV1, frame.v1.hasPairedKeyEncryption else { throw NearbyError.protocolError("Expected paired key encryption") }
            try sendSetupFrame(pairedKeyResultFrame())
            state = .sentPairedKeyResult
        case .sentPairedKeyResult:
            guard frame.hasV1, frame.v1.hasPairedKeyResult else { throw NearbyError.protocolError("Expected paired key result") }
            state = .gotPairedKeyResult
        case .gotPairedKeyResult:
            // Some phones send other setup frames first; wait for the introduction instead of failing.
            guard frame.hasV1, frame.v1.hasIntroduction else { return }
            try processIntroduction(frame)
        default:
            // E.g. the sender's own accept and progress updates; nothing to do.
            break
        }
    }

    // MARK: Introduction and consent

    private func processIntroduction(_ frame: Sharing_Nearby_Frame) throws {
        guard frame.hasV1, frame.v1.hasIntroduction else { throw NearbyError.protocolError("Expected introduction") }
        handshakeTimeout?.cancel()
        let intro = frame.v1.introduction
        var list: [Incoming] = []
        for file in intro.fileMetadata {
            list.append(Incoming(payloadID: file.payloadID, name: Self.sanitize(file.name), size: file.size, isText: false))
        }
        for text in intro.textMetadata {
            let stamp = Self.stamp.string(from: Date())
            let base = text.textTitle.isEmpty ? (text.type == .url ? "Link" : "Text") : Self.sanitize(text.textTitle)
            list.append(Incoming(payloadID: text.payloadID, name: "\(base) \(stamp).txt", size: text.size, isText: true))
        }
        guard !list.isEmpty, list.allSatisfy({ $0.size >= 0 }) else {
            rejectTransfer(.unsupportedAttachmentType)
            return
        }
        items = list
        totalBytes = list.reduce(0) { $0 + $1.size }
        state = .waitingForConsent
        requestReported = true
        onRequest?(senderName, list.map { TransferFile(name: $0.name, size: $0.size) }, keys?.pin ?? "")
    }

    /// The user's answer. Must be called on the engine queue.
    func decide(accept: Bool) {
        guard state == .waitingForConsent, !isClosed else { return }
        guard accept else { rejectTransfer(.reject); return }
        if let free = try? downloads.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < totalBytes {
            rejectTransfer(.notEnoughSpace)
            return
        }
        do {
            try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            var reserved = Set<String>()
            for i in items.indices where !items[i].isText {
                let final = Self.uniqueURL(in: downloads, name: items[i].name, reserved: &reserved)
                let part = URL(fileURLWithPath: final.path + ".part")
                guard FileManager.default.createFile(atPath: part.path, contents: nil) else {
                    throw NearbyError.inputOutput("Can't write to the downloads folder")
                }
                items[i].finalURL = final
                items[i].partURL = part
                items[i].handle = try FileHandle(forWritingTo: part)
            }
            var response = Sharing_Nearby_Frame()
            response.version = .v1
            response.v1.type = .response
            response.v1.connectionResponse.status = .accept
            state = .receiving
            try sendSetupFrame(response)
        } catch {
            fail(error)
        }
    }

    private func rejectTransfer(_ status: Sharing_Nearby_ConnectionResponseFrame.Status) {
        var frame = Sharing_Nearby_Frame()
        frame.version = .v1
        frame.v1.type = .response
        frame.v1.connectionResponse.status = status
        try? sendSetupFrame(frame)
        sendDisconnection()
        end(.failed(status == .notEnoughSpace ? "Not enough disk space" : "Transfer declined"))
    }

    // MARK: Payloads

    override func processFileChunk(_ transfer: Location_Nearby_Connections_PayloadTransferFrame) throws {
        guard state == .receiving else { throw NearbyError.protocolError("Data before consent") }
        guard let index = items.firstIndex(where: { $0.payloadID == transfer.payloadHeader.id && !$0.isText }) else {
            throw NearbyError.protocolError("Unknown file payload id \(transfer.payloadHeader.id) (header type \(transfer.payloadHeader.type), total \(transfer.payloadHeader.totalSize))")
        }
        // The introduction's size can differ from what is actually sent (e.g. photos the
        // phone re-encodes); the payload header carries the real total, so trust it.
        let headerTotal = transfer.payloadHeader.totalSize
        if headerTotal > 0, headerTotal != items[index].size {
            totalBytes += headerTotal - items[index].size
            items[index].size = headerTotal
        }
        let chunk = transfer.payloadChunk
        guard chunk.offset == items[index].received else {
            throw NearbyError.protocolError("Unexpected offset \(chunk.offset) for \(items[index].name), expected \(items[index].received)")
        }
        if chunk.hasBody, !chunk.body.isEmpty {
            guard items[index].received + Int64(chunk.body.count) <= items[index].size else {
                throw NearbyError.protocolError("\(items[index].name) larger than announced: \(items[index].size) announced, header total \(transfer.payloadHeader.totalSize), got \(items[index].received + Int64(chunk.body.count))")
            }
            try items[index].handle?.write(contentsOf: chunk.body)
            items[index].received += Int64(chunk.body.count)
            receivedBytes += Int64(chunk.body.count)
            reportProgress()
        }
        if chunk.flags & 1 == 1 { try complete(index) }
    }

    override func processBytesPayload(_ data: Data, id: Int64) throws -> Bool {
        // Phones may send a (small) file in one BYTES payload under the file's payload ID
        // instead of FILE chunks; NearDrop and QuickDrop accept this too.
        if let index = items.firstIndex(where: { $0.payloadID == id && !$0.isText }) {
            guard state == .receiving else { throw NearbyError.protocolError("Data before consent") }
            try items[index].handle?.write(contentsOf: data)
            items[index].received = Int64(data.count)
            items[index].size = Int64(data.count)
            receivedBytes += Int64(data.count)
            reportProgress()
            try complete(index)
            return true
        }
        guard let index = items.firstIndex(where: { $0.payloadID == id && $0.isText }) else { return false }
        guard state == .receiving else { throw NearbyError.protocolError("Data before consent") }
        var reserved = Set<String>()
        let url = Self.uniqueURL(in: downloads, name: items[index].name, reserved: &reserved)
        try data.write(to: url, options: .atomic)
        items[index].finalURL = url
        receivedBytes += Int64(data.count)
        try complete(index)
        return true
    }

    /// Finalizes one item; when it was the last, says goodbye and finishes.
    private func complete(_ index: Int) throws {
        var item = items[index]
        if let part = item.partURL, let final = item.finalURL {
            try item.handle?.close()
            item.handle = nil
            guard item.received == item.size else {
                throw NearbyError.protocolError("\(item.name) ended early: \(item.received) of \(item.size) bytes")
            }
            var target = final
            if FileManager.default.fileExists(atPath: target.path) {
                var reserved = Set<String>()
                target = Self.uniqueURL(in: downloads, name: final.lastPathComponent, reserved: &reserved)
            }
            try FileManager.default.moveItem(at: part, to: target)
            item.partURL = nil
            item.finalURL = target
        }
        if let url = item.finalURL {
            Self.quarantine(url)
            saved.append(url)
        }
        items.remove(at: index)
        if items.isEmpty {
            sendDisconnection()
            end(.finished(saved))
        }
    }

    private func reportProgress() {
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds - lastProgress.uptimeNanoseconds >= 250_000_000 else { return }
        lastProgress = now
        onProgress?(receivedBytes, totalBytes)
    }

    // MARK: File naming

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    /// A safe single path component: no directories, no leading dots, no separators.
    static func sanitize(_ name: String) -> String {
        var s = (name.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        s = s.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s == ".." { s = "file" }
        return String(s.prefix(200))
    }

    /// `name`, `name (1).ext`, ... — avoids existing files, their `.part` siblings and names already handed out.
    static func uniqueURL(in dir: URL, name: String, reserved: inout Set<String>) -> URL {
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = name
        var counter = 0
        func taken(_ n: String) -> Bool {
            let path = dir.appendingPathComponent(n).path
            return reserved.contains(n) || fm.fileExists(atPath: path) || fm.fileExists(atPath: path + ".part")
        }
        while taken(candidate) {
            counter += 1
            candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
        }
        reserved.insert(candidate)
        return dir.appendingPathComponent(candidate)
    }

    /// Marks the file as downloaded from the internet so Gatekeeper checks it on first open.
    static func quarantine(_ url: URL) {
        let value = String(format: "0083;%08x;NotChi;", Int(Date().timeIntervalSince1970))
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }
}
