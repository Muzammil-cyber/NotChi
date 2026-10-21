import Foundation
import Observation

/// Clipboard history, newest first, persisted as JSON.
@MainActor
@Observable
final class ClipboardStore {
    private(set) var items: [ClipItem] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL = AppPaths.support.appendingPathComponent("clipboard.json")

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded
        }
    }

    func add(_ item: ClipItem) {
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            // Duplicate: bump the existing entry and drop the freshly written image copy.
            if let new = item.imageFile, new != items[index].imageFile { removeImageFile(new) }
            var existing = items.remove(at: index)
            existing.date = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(item, at: 0)
        }
        enforceLimit()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        remove(at: index)
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        scheduleSave()
    }

    /// Removes everything except pinned items.
    func clear() {
        for index in items.indices.reversed() where !items[index].pinned { remove(at: index) }
        scheduleSave()
    }

    func saveNow() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func enforceLimit() {
        let limit = max(Settings.shared.clipboardLimit, 1)
        while items.count > limit, let index = items.lastIndex(where: { !$0.pinned }) { remove(at: index) }
    }

    private func remove(at index: Int) {
        let item = items.remove(at: index)
        if let file = item.imageFile { removeImageFile(file) }
    }

    private func removeImageFile(_ file: String) {
        try? FileManager.default.removeItem(at: ClipItem.imageDirectory.appendingPathComponent(file))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
