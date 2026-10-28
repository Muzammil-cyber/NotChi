// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Foundation

/// Re-indents or minifies JSON text without touching key order or number spelling, which
/// round-tripping through `JSONSerialization` would not preserve.
enum JSONFormatter {
    /// `indent` is one level of indentation, or nil to minify.
    static func format(_ text: String, indent: String?) -> Result<String, TransformError> {
        do {
            _ = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        } catch {
            return .failure(TransformError(describe(error)))
        }
        // JSONSerialization is lenient about trailing commas, which strict parsers reject.
        guard let formatted = reindent(text, indent: indent) else {
            return .failure(TransformError("Not valid JSON: trailing comma"))
        }
        return .success(formatted)
    }

    private static func describe(_ error: Error) -> String {
        let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? ""
        if let range = detail.range(of: #"line (\d+)"#, options: .regularExpression) {
            return "Not valid JSON at \(detail[range])"
        }
        return "Not valid JSON"
    }

    /// Nil when a container ends with a comma.
    private static func reindent(_ text: String, indent: String?) -> String? {
        let scalars = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var depth = 0
        var inString = false
        var escaped = false
        var previous: Unicode.Scalar?

        func append(_ string: String) { out.append(contentsOf: string.unicodeScalars) }
        func newline() {
            guard let indent else { return }
            append("\n")
            append(String(repeating: indent, count: depth))
        }

        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            defer {
                i += 1
                if !c.properties.isWhitespace { previous = scalars[min(i - 1, scalars.count - 1)] }
            }
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                out.append(c)
                // Keep empty containers as {} / [].
                var j = i + 1
                while j < scalars.count, scalars[j].properties.isWhitespace { j += 1 }
                if j < scalars.count, scalars[j] == (c == "{" ? "}" : "]") {
                    out.append(scalars[j])
                    i = j
                } else {
                    depth += 1
                    newline()
                }
            case "}", "]":
                if previous == "," { return nil }
                depth -= 1
                newline()
                out.append(c)
            case ",":
                out.append(c)
                newline()
            case ":":
                append(indent == nil ? ":" : ": ")
            default:
                if !c.properties.isWhitespace { out.append(c) }
            }
        }
        return String(out)
    }
}
