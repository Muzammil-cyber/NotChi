import Foundation

/// A file offered in, or sent by, a transfer.
struct TransferFile: Sendable, Equatable, Hashable {
    let name: String
    let size: Int64
}

/// An Android phone visible to Quick Share on the local network.
struct QuickShareDevice: Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// What the notch shows for an ongoing or just-finished phone transfer.
struct TransferActivity: Identifiable, Equatable {
    enum Channel: Equatable { case airDrop, quickShare }
    enum Direction: Equatable { case incoming, outgoing }

    enum Phase: Equatable {
        /// Android wants to send; nothing is written until the user accepts.
        case incomingRequest(pin: String)
        /// Sending to Android: QR shown, waiting for the phone to appear.
        case waitingForPhone(qr: URL, devices: [QuickShareDevice])
        case connecting(pin: String?)
        case transferring(done: Int64, total: Int64, bytesPerSecond: Double)
        case finished(saved: [URL])
        case failed(String)
    }

    let id: UUID
    var channel: Channel
    var direction: Direction
    var deviceName: String
    var files: [TransferFile]
    var phase: Phase

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    var summary: String {
        guard let first = files.first else { return "Files" }
        return files.count == 1 ? first.name : "\(first.name) +\(files.count - 1) more"
    }
}
