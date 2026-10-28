// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import Foundation

/// The utilities in the Text tool. A fixed set; the detector picks one from what was copied.
enum TextTool: String, CaseIterable, Identifiable {
    case json, jwt, base64, url, time, hash, uuid, color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .json: "JSON"
        case .jwt: "JWT"
        case .base64: "Base64"
        case .url: "URL"
        case .time: "Time"
        case .hash: "Hash"
        case .uuid: "UUID"
        case .color: "Color"
        }
    }

    var systemImage: String {
        switch self {
        case .json: "curlybraces"
        case .jwt: "key"
        case .base64: "number"
        case .url: "link"
        case .time: "clock"
        case .hash: "number.square"
        case .uuid: "barcode"
        case .color: "paintpalette"
        }
    }

    /// Base64 and URL run either way; the others have one direction.
    var hasDirection: Bool { self == .base64 || self == .url }
}

enum Direction {
    case encode, decode

    var flipped: Direction { self == .encode ? .decode : .encode }
    var title: String { self == .encode ? "Encode" : "Decode" }
}

enum JSONIndent: String, CaseIterable, Identifiable {
    case two, four, tab, minified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .two: "2 spaces"
        case .four: "4 spaces"
        case .tab: "Tab"
        case .minified: "Minified"
        }
    }

    /// One level of indentation; nil means no whitespace at all.
    var unit: String? {
        switch self {
        case .two: "  "
        case .four: "    "
        case .tab: "\t"
        case .minified: nil
        }
    }
}

/// One line or block of a tool's result. Labeled rows copy on click.
struct ToolRow: Identifiable, Equatable {
    let id = UUID()
    var label: String?
    var value: String
    /// Small status next to the label ("expired", "not verified").
    var tag: String?
    var tagIsWarning = false
    /// Red, green, blue, alpha in 0...1, drawn as a swatch (Color tool).
    var swatch: [Double]?
    /// Multi-line blocks (JSON) are monospaced and scroll; short values sit on one line.
    var isBlock = false
}

struct ToolOutput: Equatable {
    var rows: [ToolRow]
    /// What the Copy button puts on the pasteboard.
    var copyText: String
}

struct TransformError: Error, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
}
