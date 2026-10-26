// NotChi — https://github.com/Muzammil-cyber/NotChi
// Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Required Notice: keep this header in copies and derivatives (see LICENSE.md).

import AppKit
import CryptoKit
import Observation
import UniformTypeIdentifiers

/// One item parked in the drop strip.
struct StashItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case file, image, text, link }

    var id = UUID()
    var kind: Kind
    var date = Date()
    var pinned = false
    var text: String?
    /// Original location of a referenced file.
    var path: String?
    var bookmark: Data?
    /// File inside `AppPaths.directory("stash")` (dropped images and copied-in files).
    var storedFile: String?
    /// Identity used to avoid stashing the same thing twice: file path, image hash or text.
    var contentKey: String?

    static var directory: URL { AppPaths.directory("stash") }

    /// Location of the underlying file. Deliberately no disk access here: views read it on
    /// every redraw, and touching a file in Desktop/Documents or on an unmounted volume can
    /// block on a privacy prompt or a mount. Moves are picked up by `StashStore.relocate`.
    var fileURL: URL? {
        if let storedFile { return Self.directory.appendingPathComponent(storedFile) }
        return path.map { URL(fileURLWithPath: $0) }
    }

    var title: String {
        switch kind {
        case .file, .image: fileURL?.lastPathComponent ?? "File"
        case .text, .link: (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Temporary shelf for dropped files, images and text. Pinned items persist; the rest expire after 24h.
@MainActor
@Observable
final class StashStore {
    private(set) var items: [StashItem] = []

    @ObservationIgnored private let fileURL = AppPaths.support.appendingPathComponent("stash.json")
    @ObservationIgnored private let lifetime: TimeInterval = 24 * 3600
    @ObservationIgnored private var expiryTimer: Timer?

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([StashItem].self, from: data) {
            items = decoded.filter(\.pinned)
        }
        removeOrphans()
        relocate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    // MARK: Adding

    func addFile(_ url: URL) {
        let key = "file:" + url.standardizedFileURL.resolvingSymlinksInPath().path
        guard !bringToFront(key: key) else { return }
        let item = StashItem(kind: .file, path: url.path, contentKey: key)
        insert(item)
        // Bookmarks let the item follow the file if it moves; creating one touches the disk.
        Task.detached(priority: .utility) { [weak self] in
            let bookmark = try? url.bookmarkData()
            await self?.setBookmark(bookmark, for: item.id)
        }
    }

    private func setBookmark(_ bookmark: Data?, for id: UUID) {
        guard let bookmark, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].bookmark = bookmark
        save()
    }

    /// Resolves bookmarks in the background (never mounting volumes or showing UI) and
    /// updates paths of files that moved since they were stashed.
    private func relocate() {
        let bookmarks = items.compactMap { item in item.bookmark.map { (item.id, $0) } }
        guard !bookmarks.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            var moved: [(UUID, String)] = []
            for (id, bookmark) in bookmarks {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                      relativeTo: nil, bookmarkDataIsStale: &stale) {
                    moved.append((id, url.path))
                }
            }
            await self?.applyLocations(moved)
        }
    }

    private func applyLocations(_ locations: [(UUID, String)]) {
        var changed = false
        for (id, path) in locations {
            if let index = items.firstIndex(where: { $0.id == id }), items[index].path != path {
                items[index].path = path
                changed = true
            }
        }
        if changed { save() }
    }

    func addImage(_ image: NSImage) {
        guard let png = image.pngData else { return }
        let key = "image:" + SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        guard !bringToFront(key: key) else { return }
        let name = UUID().uuidString + ".png"
        guard (try? png.write(to: StashItem.directory.appendingPathComponent(name))) != nil else { return }
        insert(StashItem(kind: .image, storedFile: name, contentKey: key))
    }

    func addText(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = "text:" + trimmed
        guard !bringToFront(key: key) else { return }
        let isLink = !trimmed.contains(where: \.isWhitespace) && ["http", "https"].contains(URL(string: trimmed)?.scheme?.lowercased() ?? "")
        insert(StashItem(kind: isLink ? .link : .text, text: string, contentKey: key))
    }

    private func insert(_ item: StashItem) {
        items.insert(item, at: 0)
        save()
    }

    /// If an item with this identity is already stashed, moves it to the front and returns true.
    private func bringToFront(key: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.contentKey == key }) else { return false }
        var existing = items.remove(at: index)
        existing.date = Date()
        items.insert(existing, at: 0)
        save()
        return true
    }

    // MARK: Actions

    func togglePin(_ item: StashItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        save()
    }

    func remove(_ item: StashItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteStoredFile(items.remove(at: index))
        save()
    }

    /// Called after the item was dropped into another app. The stored file (if any) is kept
    /// for a minute because the receiving app may still be copying it.
    func removeAfterDragOut(_ item: StashItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        save()
        guard removed.storedFile != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            MainActor.assumeIsolated { self?.deleteStoredFile(removed) }
        }
    }

    /// Removes every unpinned item; pinned ones stay.
    func clearUnpinned() {
        items.filter { !$0.pinned }.forEach(deleteStoredFile)
        items.removeAll { !$0.pinned }
        save()
    }

    /// Duplicates a referenced file into the stash folder so it survives the original moving.
    func copyIntoStash(_ item: StashItem) {
        guard item.kind == .file, item.storedFile == nil, let source = item.fileURL,
              items.contains(where: { $0.id == item.id }) else { return }
        let name = UUID().uuidString + "-" + source.lastPathComponent
        let destination = StashItem.directory.appendingPathComponent(name)
        // Copying can be slow (big files, network volumes) or prompt for folder access.
        Task.detached(priority: .utility) { [weak self] in
            let copied = (try? FileManager.default.copyItem(at: source, to: destination)) != nil
            await self?.finishCopy(item.id, name: copied ? name : nil)
        }
    }

    private func finishCopy(_ id: UUID, name: String?) {
        guard let name, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].storedFile = name
        save()
    }

    func revealInFinder(_ item: StashItem) {
        if let url = item.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// Puts the item on the pasteboard (no paste).
    func copy(_ item: StashItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .file:
            if let url = item.fileURL { pb.writeObjects([url as NSURL]) }
        case .image:
            if let url = item.fileURL, let png = try? Data(contentsOf: url) {
                pb.setData(png, forType: .png)
                if let tiff = NSImage(data: png)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .text, .link:
            pb.setString(item.text ?? "", forType: .string)
        }
        Paster.ignoredChangeCount = pb.changeCount
    }

    /// What gets placed on the drag pasteboard: file URLs for files and images, URLs for links.
    func pasteboardWriter(for item: StashItem) -> NSPasteboardWriting? {
        switch item.kind {
        case .file, .image:
            return item.fileURL as NSURL?
        case .link:
            let trimmed = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (URL(string: trimmed) as NSURL?) ?? (trimmed as NSString)
        case .text:
            return (item.text ?? "") as NSString
        }
    }

    // MARK: Lifecycle

    /// Drops unpinned items (and their files) and persists the pinned ones. Called on quit.
    func shutdown() {
        expiryTimer?.invalidate()
        for item in items where !item.pinned { deleteStoredFile(item) }
        items.removeAll { !$0.pinned }
        save()
    }

    private func expire() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        let stale = items.filter { !$0.pinned && $0.date < cutoff }
        guard !stale.isEmpty else { return }
        stale.forEach(deleteStoredFile)
        items.removeAll { item in stale.contains { $0.id == item.id } }
        save()
    }

    private func save() {
        let pinned = items.filter(\.pinned)
        if let data = try? JSONEncoder().encode(pinned) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func deleteStoredFile(_ item: StashItem) {
        if let name = item.storedFile { try? FileManager.default.removeItem(at: StashItem.directory.appendingPathComponent(name)) }
    }

    /// Removes stash files left over from unpinned items of a previous run.
    private func removeOrphans() {
        let keep = Set(items.compactMap(\.storedFile))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: StashItem.directory.path)) ?? []
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: StashItem.directory.appendingPathComponent(file))
        }
    }
}
