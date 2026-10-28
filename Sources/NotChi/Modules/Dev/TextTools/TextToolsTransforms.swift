// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import CryptoKit
import Foundation

/// Pure functions behind each Text tool. No state, so they're cheap to call on every keystroke.
enum TextTransforms {
    /// Larger input is refused rather than frozen on.
    static let maxInputBytes = 1_000_000

    static func run(_ tool: TextTool, input: String, direction: Direction, indent: JSONIndent) -> Result<ToolOutput, TransformError> {
        guard input.utf8.count <= maxInputBytes else { return .failure(TransformError("Input is too large")) }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tool {
        case .json: return json(trimmed, indent: indent)
        case .jwt: return jwt(trimmed)
        case .base64: return base64(input, direction: direction)
        case .url: return url(input, direction: direction)
        case .time: return time(trimmed)
        case .hash: return hash(input)
        case .uuid: return uuid(trimmed)
        case .color: return color(trimmed)
        }
    }

    // MARK: JSON

    static func json(_ text: String, indent: JSONIndent) -> Result<ToolOutput, TransformError> {
        JSONFormatter.format(text, indent: indent.unit).map { formatted in
            ToolOutput(rows: [ToolRow(value: formatted, isBlock: true)], copyText: formatted)
        }
    }

    // MARK: JWT

    static func jwt(_ text: String) -> Result<ToolOutput, TransformError> {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 || parts.count == 2,
              let headerData = base64URLDecode(parts[0]), let payloadData = base64URLDecode(parts[1]),
              let header = String(data: headerData, encoding: .utf8), let payload = String(data: payloadData, encoding: .utf8),
              case .success(let headerText) = JSONFormatter.format(header, indent: "  "),
              case .success(let payloadText) = JSONFormatter.format(payload, indent: "  ")
        else { return .failure(TransformError("Not a valid JWT")) }

        var rows = [
            ToolRow(label: "Header", value: headerText, isBlock: true),
            ToolRow(label: "Payload", value: payloadText, isBlock: true),
        ]
        if let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            let now = Date()
            for (key, name) in [("exp", "Expires"), ("nbf", "Not before"), ("iat", "Issued")] {
                guard let seconds = (claims[key] as? NSNumber)?.doubleValue else { continue }
                let date = Date(timeIntervalSince1970: seconds)
                var row = ToolRow(label: name, value: localString(date))
                if key == "exp" { row.tag = date < now ? "expired" : "valid"; row.tagIsWarning = date < now }
                if key == "nbf", date > now { row.tag = "not yet valid"; row.tagIsWarning = true }
                rows.append(row)
            }
        }
        rows.append(ToolRow(label: "Signature", value: parts.count == 3 ? "\(parts[2].count) characters" : "none",
                            tag: "not verified"))
        return .success(ToolOutput(rows: rows, copyText: payloadText))
    }

    // MARK: Base64

    static func base64(_ input: String, direction: Direction) -> Result<ToolOutput, TransformError> {
        switch direction {
        case .encode:
            let encoded = Data(input.utf8).base64EncodedString()
            let urlSafe = encoded.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            var rows = [ToolRow(value: encoded, isBlock: true)]
            if urlSafe != encoded { rows.append(ToolRow(label: "URL-safe", value: urlSafe)) }
            return .success(ToolOutput(rows: rows, copyText: encoded))
        case .decode:
            guard let data = base64Decode(input) else { return .failure(TransformError("Not valid Base64")) }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(TransformError("Decodes to binary data (\(data.count) bytes), not text"))
            }
            return .success(ToolOutput(rows: [ToolRow(value: text, isBlock: true)], copyText: text))
        }
    }

    /// Accepts standard and URL-safe alphabets, with or without padding or line breaks.
    static func base64Decode(_ string: String) -> Data? {
        var s = string.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !s.isEmpty else { return nil }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        if s.count % 4 == 1 { return nil }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }

    static func base64URLDecode(_ string: String) -> Data? { base64Decode(string) }

    // MARK: URL

    private static let componentAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func url(_ input: String, direction: Direction) -> Result<ToolOutput, TransformError> {
        switch direction {
        case .encode:
            let encoded = input.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? input
            return .success(ToolOutput(rows: [ToolRow(value: encoded, isBlock: true)], copyText: encoded))
        case .decode:
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let decoded = trimmed.removingPercentEncoding else { return .failure(TransformError("Invalid percent-encoding")) }
            var rows = [ToolRow(value: decoded, isBlock: true)]
            rows += urlParts(trimmed)
            return .success(ToolOutput(rows: rows, copyText: decoded))
        }
    }

    /// Breakdown of an absolute URL into its components, for inspecting long links.
    private static func urlParts(_ text: String) -> [ToolRow] {
        guard let components = URLComponents(string: text), components.scheme != nil, components.host != nil else { return [] }
        var rows: [ToolRow] = []
        if let scheme = components.scheme { rows.append(ToolRow(label: "Scheme", value: scheme)) }
        if let host = components.host { rows.append(ToolRow(label: "Host", value: host)) }
        if let port = components.port { rows.append(ToolRow(label: "Port", value: String(port))) }
        if !components.path.isEmpty { rows.append(ToolRow(label: "Path", value: components.path)) }
        for item in components.queryItems ?? [] {
            rows.append(ToolRow(label: item.name, value: item.value ?? ""))
        }
        if let fragment = components.fragment { rows.append(ToolRow(label: "Fragment", value: fragment)) }
        return rows
    }

    // MARK: Time

    static func time(_ text: String) -> Result<ToolOutput, TransformError> {
        guard !text.isEmpty else { return .failure(TransformError("Enter a Unix timestamp or a date")) }
        var assumedLocal = false
        let date: Date
        if let number = Double(text) {
            // 13 digits is milliseconds; anything past year ~5138 in seconds must be.
            date = Date(timeIntervalSince1970: abs(number) >= 1e11 ? number / 1000 : number)
        } else if let parsed = parseDate(text) {
            date = parsed.date
            assumedLocal = parsed.assumedLocal
        } else {
            return .failure(TransformError("Couldn't read that as a time"))
        }

        let seconds = Int64(date.timeIntervalSince1970.rounded(.down))
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let rows = [
            ToolRow(label: "Unix (s)", value: String(seconds)),
            ToolRow(label: "Unix (ms)", value: String(millis)),
            ToolRow(label: "UTC", value: iso.string(from: date)),
            ToolRow(label: "Local", value: localString(date), tag: assumedLocal ? "assumed local" : nil),
            ToolRow(label: "Relative", value: relative.localizedString(for: date, relativeTo: Date())),
        ]
        return .success(ToolOutput(rows: rows, copyText: iso.string(from: date)))
    }

    private static func parseDate(_ text: String) -> (date: Date, assumedLocal: Bool)? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return (date, false) }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return (date, false) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return (date, true) }
        }
        return nil
    }

    private static func localString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss xxx"
        return formatter.string(from: date)
    }

    // MARK: Hash

    static func hash(_ input: String) -> Result<ToolOutput, TransformError> {
        guard !input.isEmpty else { return .failure(TransformError("Enter text to hash")) }
        let data = Data(input.utf8)
        func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
            digest.map { String(format: "%02x", $0) }.joined()
        }
        let sha256 = hex(SHA256.hash(data: data))
        let rows = [
            ToolRow(label: "MD5", value: hex(Insecure.MD5.hash(data: data))),
            ToolRow(label: "SHA-1", value: hex(Insecure.SHA1.hash(data: data))),
            ToolRow(label: "SHA-256", value: sha256),
            ToolRow(label: "SHA-512", value: hex(SHA512.hash(data: data))),
        ]
        return .success(ToolOutput(rows: rows, copyText: sha256))
    }

    // MARK: UUID

    static func uuid(_ text: String) -> Result<ToolOutput, TransformError> {
        guard let uuid = UUID(uuidString: text) else { return .failure(TransformError("Not a valid UUID")) }
        let canonical = uuid.uuidString.lowercased()
        let chars = Array(canonical)
        let version = chars[14].wholeNumberValue ?? 0
        let variant = "89ab".contains(chars[19]) ? "RFC 4122" : "other"
        let rows = [
            ToolRow(label: "Lowercase", value: canonical),
            ToolRow(label: "Uppercase", value: canonical.uppercased()),
            ToolRow(label: "No dashes", value: canonical.replacingOccurrences(of: "-", with: "")),
            ToolRow(label: "Version", value: version == 0 ? "unknown" : "v\(version)", tag: variant),
        ]
        return .success(ToolOutput(rows: rows, copyText: canonical))
    }

    // MARK: Color

    /// Red, green, blue, alpha in 0...1. Needs a `#`, `rgb(`/`rgba(` or `hsl(`/`hsla(` form so
    /// bare words and numbers aren't read as colors.
    static func parseColor(_ text: String) -> [Double]? {
        let s = text.lowercased().trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            guard hex.allSatisfy(\.isHexDigit), [3, 4, 6, 8].contains(hex.count) else { return nil }
            let digits = hex.count <= 4 ? hex.flatMap { [$0, $0] } : Array(hex)
            let bytes = stride(from: 0, to: digits.count, by: 2).compactMap { UInt8(String(digits[$0...$0 + 1]), radix: 16) }
            guard bytes.count == digits.count / 2 else { return nil }
            var values = bytes.map { Double($0) / 255 }
            if values.count == 3 { values.append(1) }
            return values
        }
        guard s.hasPrefix("rgb") || s.hasPrefix("hsl"), s.hasSuffix(")") else { return nil }
        // Arguments may be comma or space separated, with an optional "/ alpha".
        let numbers = s.drop(while: { $0 != "(" }).dropFirst().dropLast()
            .replacingOccurrences(of: "deg", with: "")
            .split(whereSeparator: { ", /".contains($0) }).map(String.init)
        guard numbers.count == 3 || numbers.count == 4 else { return nil }
        func value(_ token: String, scale: Double) -> Double {
            token.hasSuffix("%") ? (Double(token.dropLast()) ?? 0) / 100 : (Double(token) ?? 0) / scale
        }
        let alpha = numbers.count == 4 ? min(max(value(numbers[3], scale: 1), 0), 1) : 1
        if s.hasPrefix("rgb") {
            let rgb = numbers.prefix(3).map { min(max(value($0, scale: 255), 0), 1) }
            return rgb + [alpha]
        }
        let hue = (Double(numbers[0]) ?? 0).truncatingRemainder(dividingBy: 360)
        let rgb = hslToRGB(h: (hue < 0 ? hue + 360 : hue) / 360,
                           s: min(max(value(numbers[1], scale: 100), 0), 1),
                           l: min(max(value(numbers[2], scale: 100), 0), 1))
        return rgb + [alpha]
    }

    static func color(_ text: String) -> Result<ToolOutput, TransformError> {
        guard let c = parseColor(text) else { return .failure(TransformError("Try #ff8800, rgb(255, 136, 0) or hsl(32, 100%, 50%)")) }
        let r = Int((c[0] * 255).rounded()), g = Int((c[1] * 255).rounded()), b = Int((c[2] * 255).rounded())
        let opaque = c[3] >= 1
        let a = Int((c[3] * 255).rounded())
        let hex = String(format: "#%02X%02X%02X", r, g, b) + (opaque ? "" : String(format: "%02X", a))
        let alpha = String(format: "%g", (c[3] * 100).rounded() / 100)
        let rgb = opaque ? "rgb(\(r), \(g), \(b))" : "rgba(\(r), \(g), \(b), \(alpha))"
        let (h, s, l) = rgbToHSL(r: c[0], g: c[1], b: c[2])
        let hsl = opaque ? "hsl(\(h), \(s)%, \(l)%)" : "hsla(\(h), \(s)%, \(l)%, \(alpha))"
        let rows = [
            ToolRow(label: "Hex", value: hex, swatch: c),
            ToolRow(label: "RGB", value: rgb),
            ToolRow(label: "HSL", value: hsl),
        ]
        return .success(ToolOutput(rows: rows, copyText: hex))
    }

    private static func rgbToHSL(r: Double, g: Double, b: Double) -> (Int, Int, Int) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        guard d > 0 else { return (0, 0, Int((l * 100).rounded())) }
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        switch maxV {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        return (Int(h.rounded()) % 360, Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> [Double] {
        guard s > 0 else { return [l, l, l] }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return [channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3)]
    }
}
