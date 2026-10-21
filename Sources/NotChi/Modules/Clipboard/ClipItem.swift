import AppKit
import CryptoKit
import ImageIO

/// One entry in the clipboard history.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, richText, code, link, image, file }

    var id = UUID()
    var kind: Kind
    var date = Date()
    var text: String?
    var rtf: Data?
    /// File name inside `AppPaths.directory("clipboard-images")`.
    var imageFile: String?
    var fileURLs: [URL]?
    var sourceBundleID: String?
    var sourceName: String?
    var contentHash: String
    var pinned = false

    static var imageDirectory: URL { AppPaths.directory("clipboard-images") }

    var imageURL: URL? { imageFile.map { Self.imageDirectory.appendingPathComponent($0) } }

    /// Short single-purpose description used in the list row.
    var preview: String {
        switch kind {
        case .image: return "Image"
        case .file:
            let names = (fileURLs ?? []).map(\.lastPathComponent)
            guard let first = names.first else { return "File" }
            return names.count > 1 ? "\(first) +\(names.count - 1) more" : first
        default: return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var systemImage: String {
        switch kind {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }

    static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Bundle identifiers of developer tools, whose copies are most likely code.
    static let devBundlePrefixes = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop", "com.jetbrains.",
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp", "com.sublimetext", "com.panic.Nova",
    ]

    static func looksLikeCode(_ text: String, sourceBundleID: String?) -> Bool {
        let symbols = CharacterSet(charactersIn: "{}();=<>[]")
        let hasSymbol = text.unicodeScalars.contains { symbols.contains($0) }
        if let id = sourceBundleID, devBundlePrefixes.contains(where: { id.hasPrefix($0) }) {
            return text.contains("\n") || hasSymbol
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return false }
        let symbolCount = text.unicodeScalars.filter { "{};()=".unicodeScalars.contains($0) }.count
        let density = Double(symbolCount) / Double(max(text.count, 1))
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        return density > 0.04 || (Double(indented) / Double(lines.count) > 0.4 && hasSymbol)
    }
}

/// Small cached image thumbnails decoded straight from disk.
@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(at url: URL, maxPixel: Int = 96) -> NSImage? {
        let key = "\(url.path)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

extension NSImage {
    /// PNG-encoded representation, converting from whatever the image holds (e.g. TIFF).
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
