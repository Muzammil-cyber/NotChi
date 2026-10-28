// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Foundation

/// Picks the Text tool that fits a piece of copied text, or nil when nothing is distinctive.
/// Order matters: the first match wins, most specific first.
enum TextToolsDetector {
    static func detect(_ text: String) -> TextTool? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.utf8.count <= TextTransforms.maxInputBytes else { return nil }
        if isJWT(s) { return .jwt }
        if isJSON(s) { return .json }
        if isTime(s) { return .time }
        if TextTransforms.parseColor(s) != nil { return .color }
        if UUID(uuidString: s) != nil { return .uuid }
        if isURL(s) { return .url }
        if isBase64(s) { return .base64 }
        return nil
    }

    private static func isJWT(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) || parts.count == 3 else { return false }
        guard parts[0].allSatisfy(isBase64URLCharacter), parts[1].allSatisfy(isBase64URLCharacter) else { return false }
        guard let data = TextTransforms.base64URLDecode(String(parts[0])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["alg"] != nil || object["typ"] != nil
    }

    private static func isBase64URLCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")
    }

    private static func isJSON(_ s: String) -> Bool {
        guard let first = s.first, first == "{" || first == "[" else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) != nil
    }

    private static func isTime(_ s: String) -> Bool {
        s.range(of: #"^-?\d{10}(\d{3})?(\.\d+)?$"#, options: .regularExpression) != nil
            || s.range(of: #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$"#, options: .regularExpression) != nil
    }

    private static func isURL(_ s: String) -> Bool {
        guard !s.contains(where: \.isWhitespace) else { return false }
        if let url = URL(string: s), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil {
            return true
        }
        return hasPercentEscape(s)
    }

    static func hasPercentEscape(_ s: String) -> Bool {
        s.range(of: #"%[0-9A-Fa-f]{2}"#, options: .regularExpression) != nil
    }

    /// Looks like Base64 only if it decodes to mostly printable UTF-8, so plain words and
    /// identifiers that happen to use the alphabet aren't misread.
    static func isBase64(_ s: String) -> Bool {
        let compact = s.filter { !$0.isWhitespace }
        guard compact.count >= 8,
              compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=-_".contains($0)) }),
              let data = TextTransforms.base64Decode(compact),
              let decoded = String(data: data, encoding: .utf8) else { return false }
        let printable = decoded.unicodeScalars.filter { !$0.properties.isWhitespace ? $0.value >= 32 : true }.count
        return Double(printable) / Double(max(decoded.unicodeScalars.count, 1)) > 0.95
    }
}
