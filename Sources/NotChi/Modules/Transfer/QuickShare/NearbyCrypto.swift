// Adapted from NearDrop by Grishka, Unlicense. ECDH/ECDSA use CryptoKit instead of SwiftECC.
import CommonCrypto
import CryptoKit
import Foundation

/// Errors raised by the Quick Share protocol layers.
enum NearbyError: Error, CustomStringConvertible {
    case protocolError(String)
    case ukey2
    case crypto(Int32)
    case inputOutput(String)

    var description: String {
        switch self {
        case .protocolError(let m): return m
        case .ukey2: return "Key exchange failed"
        case .crypto(let status): return "Encryption error (\(status))"
        case .inputOutput(let m): return m
        }
    }
}

extension Data {
    /// URL-safe base64 without padding.
    func urlSafeBase64() -> String {
        base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    init?(urlSafeBase64 string: String) {
        var s = string.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s, options: .ignoreUnknownCharacters)
    }

    static func random(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }
}

/// Key schedule and primitives shared by both ends of a Quick Share connection.
enum NearbyCrypto {
    /// Keys and PIN derived at the end of UKEY2.
    struct SessionKeys {
        let authKey: Data
        let decryptKey: Data
        let encryptKey: Data
        let recvHmacKey: SymmetricKey
        let sendHmacKey: SymmetricKey

        var pin: String { NearbyCrypto.pin(from: authKey) }
    }

    // MARK: UKEY2

    /// UKEY2 encodes P-256 coordinates as big-endian two's complement integers.
    static func signedBytes(_ coordinate: Data) -> Data {
        var bytes = Data(coordinate.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = Data([0]) }
        if bytes[bytes.startIndex] & 0x80 != 0 { bytes.insert(0, at: bytes.startIndex) }
        return bytes
    }

    /// Normalizes a two's complement coordinate (leading sign byte, or shorter than 32 bytes) to 32 bytes.
    static func fixedCoordinate(_ data: Data) -> Data? {
        let stripped = Data(data.drop(while: { $0 == 0 }))
        guard stripped.count <= 32 else { return nil }
        return Data(repeating: 0, count: 32 - stripped.count) + stripped
    }

    static func genericPublicKey(for key: P256.KeyAgreement.PublicKey) -> Securemessage_GenericPublicKey {
        let raw = key.rawRepresentation
        var pkey = Securemessage_GenericPublicKey()
        pkey.type = .ecP256
        pkey.ecP256PublicKey = Securemessage_EcP256PublicKey()
        pkey.ecP256PublicKey.x = signedBytes(raw.prefix(32))
        pkey.ecP256PublicKey.y = signedBytes(raw.suffix(32))
        return pkey
    }

    static func publicKey(from generic: Securemessage_GenericPublicKey) throws -> P256.KeyAgreement.PublicKey {
        guard generic.hasEcP256PublicKey,
              let x = fixedCoordinate(generic.ecP256PublicKey.x),
              let y = fixedCoordinate(generic.ecP256PublicKey.y),
              let key = try? P256.KeyAgreement.PublicKey(rawRepresentation: x + y) else { throw NearbyError.ukey2 }
        return key
    }

    /// Completes UKEY2: ECDH, auth string, next protocol secret and the four SecureMessage keys.
    /// `clientInit` / `serverInit` are the raw UKEY2 messages as sent on the wire.
    static func deriveKeys(
        privateKey: P256.KeyAgreement.PrivateKey, peerKey: P256.KeyAgreement.PublicKey,
        clientInit: Data, serverInit: Data, isServer: Bool
    ) throws -> SessionKeys {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peerKey)
        // Hash the full 32-byte x coordinate, leading zeros included. That is what Google's
        // UKEY2 does (Java `KeyAgreement.generateSecret()` → SHA-256 in EnrollmentCryptoOps) and
        // what rquickshare does. NearDrop strips leading zeros (BigInt magnitude), which breaks
        // the ~1 in 256 handshakes whose secret starts with 0x00.
        let x = secret.withUnsafeBytes { Data($0) }
        let derived = SymmetricKey(data: Data(SHA256.hash(data: x)))

        let info = clientInit + serverInit
        let auth = hkdf(derived, salt: Data("UKEY2 v1 auth".utf8), info: info)
        let next = SymmetricKey(data: hkdf(derived, salt: Data("UKEY2 v1 next".utf8), info: info))

        let d2dSalt = Data(SHA256.hash(data: Data("D2D".utf8)))
        let d2dClient = SymmetricKey(data: hkdf(next, salt: d2dSalt, info: Data("client".utf8)))
        let d2dServer = SymmetricKey(data: hkdf(next, salt: d2dSalt, info: Data("server".utf8)))

        let smSalt = Data(SHA256.hash(data: Data("SecureMessage".utf8)))
        let clientEnc = hkdf(d2dClient, salt: smSalt, info: Data("ENC:2".utf8))
        let clientSig = SymmetricKey(data: hkdf(d2dClient, salt: smSalt, info: Data("SIG:1".utf8)))
        let serverEnc = hkdf(d2dServer, salt: smSalt, info: Data("ENC:2".utf8))
        let serverSig = SymmetricKey(data: hkdf(d2dServer, salt: smSalt, info: Data("SIG:1".utf8)))

        return isServer
            ? SessionKeys(authKey: auth, decryptKey: clientEnc, encryptKey: serverEnc, recvHmacKey: clientSig, sendHmacKey: serverSig)
            : SessionKeys(authKey: auth, decryptKey: serverEnc, encryptKey: clientEnc, recvHmacKey: serverSig, sendHmacKey: clientSig)
    }

    static func hkdf(_ ikm: SymmetricKey, salt: Data, info: Data, length: Int = 32) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: length)
        return key.withUnsafeBytes { Data($0) }
    }

    /// The 4-digit PIN both devices show, from Chromium's nearby_sharing_service_impl.
    static func pin(from authKey: Data) -> String {
        var hash = 0
        var multiplier = 1
        for byte in authKey {
            hash = (hash + Int(Int8(bitPattern: byte)) * multiplier) % 9973
            multiplier = (multiplier * 31) % 9973
        }
        return String(format: "%04d", abs(hash))
    }

    // MARK: SecureMessage payload encryption

    static func aesCBC(encrypt: Bool, key: Data, iv: Data, input: Data) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let outCapacity = output.count
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                iv.withUnsafeBytes { ivp in
                    key.withUnsafeBytes { keyp in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyp.baseAddress, key.count, ivp.baseAddress,
                            inp.baseAddress, input.count, out.baseAddress, outCapacity, &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw NearbyError.crypto(status) }
        return output.prefix(written)
    }
}

/// Endpoint info: device type, name and optional TLV records. Used in the mDNS `n` TXT record and
/// the connection request.
struct NearbyEndpointInfo {
    var name: String?
    /// 1 = phone, 2 = tablet, 3 = laptop
    var deviceType: Int
    var qrCodeData: Data?

    init(name: String?, deviceType: Int = 3, qrCodeData: Data? = nil) {
        self.name = name
        self.deviceType = deviceType
        self.qrCodeData = qrCodeData
    }

    init?(data: Data) {
        let d = [UInt8](data)
        guard d.count > 17 else { return nil }
        let hasName = d[0] & 0x10 == 0
        var offset = 17
        if hasName {
            let length = Int(d[17])
            guard d.count >= 18 + length, let n = String(bytes: d[18..<18 + length], encoding: .utf8) else { return nil }
            name = n
            offset = 18 + length
        }
        deviceType = Int(d[0] & 7) >> 1
        while d.count - offset > 2 {
            let type = d[offset]
            let length = Int(d[offset + 1])
            offset += 2
            guard d.count - offset >= length else { break }
            if type == 1 { qrCodeData = Data(d[offset..<offset + length]) }
            offset += length
        }
    }

    /// Visible-device encoding with random "metadata key" bytes.
    func serialize() -> Data {
        var out = Data([UInt8(deviceType << 1)])
        out.append(Data.random(16))
        var nameBytes = Array((name ?? "").utf8.prefix(255))
        while String(bytes: nameBytes, encoding: .utf8) == nil, !nameBytes.isEmpty { nameBytes.removeLast() }
        out.append(UInt8(nameBytes.count))
        out.append(contentsOf: nameBytes)
        return out
    }
}

/// The key pair behind a QR code shown by the sender, and the tokens derived from it.
struct NearbyQRKey {
    private let signingKey = P256.Signing.PrivateKey()
    /// Version bytes (0, 0) followed by the compressed public key (02/03 || x).
    let keyData: Data
    let advertisingToken: Data
    let nameKey: SymmetricKey

    init() {
        keyData = Data([0, 0]) + signingKey.publicKey.compressedRepresentation
        let ikm = SymmetricKey(data: keyData)
        advertisingToken = NearbyCrypto.hkdf(ikm, salt: Data(), info: Data("advertisingContext".utf8), length: 16)
        nameKey = SymmetricKey(data: NearbyCrypto.hkdf(ikm, salt: Data(), info: Data("encryptionKey".utf8), length: 16))
    }

    var url: URL { URL(string: "https://quickshare.google/qrcode#key=\(keyData.urlSafeBase64())")! }

    /// IEEE P1363 (r || s) signature of the UKEY2 auth key, which lets the phone skip its prompt.
    func signature(of authKey: Data) -> Data? {
        (try? signingKey.signature(for: authKey))?.rawRepresentation
    }

    /// Name of a hidden device whose TLV holds the AES-GCM encrypted name (IV || ciphertext || tag).
    func decryptName(_ blob: Data) -> String? {
        guard blob.count > 28, let box = try? AES.GCM.SealedBox(combined: blob),
              let plain = try? AES.GCM.open(box, using: nameKey, authenticating: advertisingToken) else { return nil }
        return String(data: plain, encoding: .utf8)
    }
}
