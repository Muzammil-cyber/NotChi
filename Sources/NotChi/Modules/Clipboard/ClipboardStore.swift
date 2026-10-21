import Foundation
import Observation

/// Clipboard history in SQLite (`clipboard.sqlite`): one row per item, images as PNG files
/// beside it. Only the rows the list shows are kept in memory, a new copy is a single
/// insert, and search uses an FTS5 trigram index so substring matches stay fast.
@MainActor
@Observable
final class ClipboardStore {
    enum KindFilter: Equatable {
        case all
        case kinds([ClipItem.Kind])
    }

    /// The current page of rows for the active search and filter: pinned first, then newest.
    private(set) var results: [ClipItem] = []
    /// Whether the history holds anything at all (drives the empty state).
    private(set) var isEmpty = true
    private(set) var hasUnpinned = false

    @ObservationIgnored private let db: SQLiteDatabase?
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var filter: KindFilter = .all
    @ObservationIgnored private var pageLimit = ClipboardStore.pageSize
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var stale = true

    private static let pageSize = 100
    /// Characters of text loaded for list rows; the full value is read when pasting.
    private static let listTextLimit = 2000

    init() {
        let url = AppPaths.support.appendingPathComponent("clipboard.sqlite")
        do {
            let db = try SQLiteDatabase(url: url)
            try Self.migrateSchema(db)
            self.db = db
            importLegacyJSON()
            removeOrphanedImages()
        } catch {
            NSLog("NotChi: clipboard database unavailable: %@", String(describing: error))
            db = nil
        }
        refreshCounts()
    }

    // MARK: Reading

    /// Sets the active search and reloads the first page.
    func search(_ text: String, filter: KindFilter) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query || filter != self.filter || stale else { return }
        query = trimmed
        self.filter = filter
        pageLimit = Self.pageSize
        reload()
    }

    /// Loads the next page when the list scrolls near its end.
    func loadMore() {
        guard results.count >= pageLimit else { return }
        pageLimit += Self.pageSize
        reload()
    }

    /// The list only refreshes while it is on screen; changes made while hidden are picked
    /// up on the next appearance.
    func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible && stale { reload() }
    }

    /// The complete item (full text and rich text), for pasting.
    func fullItem(_ item: ClipItem) -> ClipItem {
        guard let db, let statement = try? db.prepare("SELECT \(Self.columns(fullText: true)) FROM clips WHERE id = ?") else { return item }
        var found: ClipItem?
        statement.bind(item.id.uuidString).rows { found = Self.item(from: $0) }
        return found ?? item
    }

    // MARK: Writing

    func add(_ item: ClipItem) {
        guard let db else { return }
        do {
            try db.transaction {
                var existing: (id: String, image: String?)?
                try db.prepare("SELECT id, image_file FROM clips WHERE content_hash = ?")
                    .bind(item.contentHash).rows { existing = ($0.string(0) ?? "", $0.string(1)) }
                if let existing {
                    // Duplicate: bump the existing row and drop the freshly written image copy.
                    if let new = item.imageFile, new != existing.image { removeImageFile(new) }
                    try db.prepare("UPDATE clips SET date = ? WHERE id = ?")
                        .bind(item.date.timeIntervalSince1970, existing.id).run()
                } else {
                    try insert(item, into: db)
                }
                try enforceLimit(db)
            }
        } catch {
            NSLog("NotChi: clipboard insert failed: %@", String(describing: error))
        }
        changed()
    }

    func delete(_ item: ClipItem) {
        guard let db else { return }
        try? db.prepare("DELETE FROM clips WHERE id = ?").bind(item.id.uuidString).run()
        if let file = item.imageFile { removeImageFile(file) }
        changed()
    }

    func togglePin(_ item: ClipItem) {
        try? db?.prepare("UPDATE clips SET pinned = NOT pinned WHERE id = ?").bind(item.id.uuidString).run()
        changed()
    }

    /// Removes everything except pinned items.
    func clear() {
        guard let db else { return }
        var files: [String] = []
        try? db.prepare("SELECT image_file FROM clips WHERE pinned = 0 AND image_file IS NOT NULL")
            .rows { if let file = $0.string(0) { files.append(file) } }
        try? db.execute("DELETE FROM clips WHERE pinned = 0")
        files.forEach(removeImageFile)
        changed()
    }

    /// Re-applies the history limit (e.g. after the setting changed).
    func applyLimit() {
        guard let db else { return }
        try? db.transaction { try enforceLimit(db) }
        changed()
    }

    // MARK: - Internals

    private func changed() {
        refreshCounts()
        if visible { reload() } else { stale = true }
    }

    private func reload() {
        stale = false
        guard let db else { results = []; return }
        var conditions: [String] = []
        var arguments: [Any?] = []
        var source = "clips"
        if !query.isEmpty {
            if query.count >= 3 {
                // Trigram FTS: case-insensitive substring match, as one quoted phrase.
                source = "clips JOIN clips_fts ON clips_fts.rowid = clips.seq"
                conditions.append("clips_fts MATCH ?")
                arguments.append("\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
            } else {
                // Trigrams need 3+ characters; short queries scan with LIKE (fine at this size).
                conditions.append("clips.search_text LIKE ? ESCAPE '\\'")
                let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
                arguments.append("%" + escaped + "%")
            }
        }
        if case .kinds(let kinds) = filter, !kinds.isEmpty {
            conditions.append("clips.kind IN (" + kinds.map { _ in "?" }.joined(separator: ",") + ")")
            arguments += kinds.map(\.rawValue)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = "SELECT \(Self.columns(fullText: false)) FROM \(source) \(whereClause) ORDER BY clips.pinned DESC, clips.date DESC LIMIT \(pageLimit)"
        var page: [ClipItem] = []
        do {
            try db.prepare(sql).bind(values: arguments).rows { if let item = Self.item(from: $0) { page.append(item) } }
        } catch {
            NSLog("NotChi: clipboard query failed: %@", String(describing: error))
        }
        if page != results { results = page }
    }

    private func refreshCounts() {
        guard let db else { return }
        var total = 0, unpinned = 0
        try? db.prepare("SELECT count(*), coalesce(sum(pinned = 0), 0) FROM clips").rows {
            total = $0.int(0)
            unpinned = $0.int(1)
        }
        if isEmpty != (total == 0) { isEmpty = total == 0 }
        if hasUnpinned != (unpinned > 0) { hasUnpinned = unpinned > 0 }
    }

    private func insert(_ item: ClipItem, into db: SQLiteDatabase) throws {
        let files = item.fileURLs.map { $0.map(\.path).joined(separator: "\n") }
        let searchText = [item.preview, item.sourceName ?? ""].joined(separator: "\n")
        try db.prepare("""
            INSERT INTO clips (id, kind, date, text, rtf, image_file, file_paths, source_bundle_id,
                               source_name, content_hash, pinned, search_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
            .bind(item.id.uuidString, item.kind.rawValue, item.date.timeIntervalSince1970, item.text, item.rtf,
                  item.imageFile, files, item.sourceBundleID, item.sourceName, item.contentHash, item.pinned, searchText)
            .run()
    }

    /// Deletes the oldest unpinned rows beyond the configured limit, with their image files.
    private func enforceLimit(_ db: SQLiteDatabase) throws {
        let limit = max(Settings.shared.clipboardLimit, 1)
        var total = 0
        try db.prepare("SELECT count(*) FROM clips").rows { total = $0.int(0) }
        let excess = total - limit
        guard excess > 0 else { return }
        var victims: [(id: String, image: String?)] = []
        try db.prepare("SELECT id, image_file FROM clips WHERE pinned = 0 ORDER BY date ASC LIMIT ?")
            .bind(excess).rows { victims.append(($0.string(0) ?? "", $0.string(1))) }
        let delete = try db.prepare("DELETE FROM clips WHERE id = ?")
        for victim in victims {
            try delete.bind(victim.id).run()
            if let file = victim.image { removeImageFile(file) }
        }
    }

    private func removeImageFile(_ file: String) {
        try? FileManager.default.removeItem(at: ClipItem.imageDirectory.appendingPathComponent(file))
    }

    /// Deletes image files no row refers to (left by crashes or older versions).
    private func removeOrphanedImages() {
        guard let db else { return }
        var referenced = Set<String>()
        try? db.prepare("SELECT image_file FROM clips WHERE image_file IS NOT NULL")
            .rows { if let file = $0.string(0) { referenced.insert(file) } }
        let directory = ClipItem.imageDirectory
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// One-time import of the JSON history written by earlier versions.
    private func importLegacyJSON() {
        let legacy = AppPaths.support.appendingPathComponent("clipboard.json")
        guard let db, let data = try? Data(contentsOf: legacy) else { return }
        guard let items = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            try? FileManager.default.removeItem(at: legacy)
            return
        }
        do {
            try db.transaction {
                // Oldest first so duplicate hashes keep the most recent copy.
                for item in items.reversed() {
                    try db.prepare("DELETE FROM clips WHERE content_hash = ?").bind(item.contentHash).run()
                    try insert(item, into: db)
                }
            }
            try? FileManager.default.removeItem(at: legacy)
            NSLog("NotChi: imported %d clipboard items from JSON", items.count)
        } catch {
            NSLog("NotChi: clipboard JSON import failed: %@", String(describing: error))
        }
    }

    // MARK: - Schema & row mapping

    private static func migrateSchema(_ db: SQLiteDatabase) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS clips (
                seq INTEGER PRIMARY KEY,
                id TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL,
                date REAL NOT NULL,
                text TEXT,
                rtf BLOB,
                image_file TEXT,
                file_paths TEXT,
                source_bundle_id TEXT,
                source_name TEXT,
                content_hash TEXT NOT NULL UNIQUE,
                pinned INTEGER NOT NULL DEFAULT 0,
                search_text TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS clips_order ON clips (pinned DESC, date DESC);
            CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts
                USING fts5(search_text, content = 'clips', content_rowid = 'seq', tokenize = 'trigram');
            CREATE TRIGGER IF NOT EXISTS clips_ai AFTER INSERT ON clips BEGIN
                INSERT INTO clips_fts (rowid, search_text) VALUES (new.seq, new.search_text);
            END;
            CREATE TRIGGER IF NOT EXISTS clips_ad AFTER DELETE ON clips BEGIN
                INSERT INTO clips_fts (clips_fts, rowid, search_text) VALUES ('delete', old.seq, old.search_text);
            END;
            CREATE TRIGGER IF NOT EXISTS clips_au AFTER UPDATE OF search_text ON clips BEGIN
                INSERT INTO clips_fts (clips_fts, rowid, search_text) VALUES ('delete', old.seq, old.search_text);
                INSERT INTO clips_fts (rowid, search_text) VALUES (new.seq, new.search_text);
            END;
            PRAGMA user_version = 1;
            """)
    }

    /// List rows skip the RTF blob and cap text length; pasting loads the full row.
    private static func columns(fullText: Bool) -> String {
        let text = fullText ? "clips.text" : "substr(clips.text, 1, \(listTextLimit))"
        let rtf = fullText ? "clips.rtf" : "NULL"
        return "clips.id, clips.kind, clips.date, \(text), \(rtf), clips.image_file, clips.file_paths, clips.source_bundle_id, clips.source_name, clips.content_hash, clips.pinned"
    }

    private static func item(from row: SQLiteDatabase.Row) -> ClipItem? {
        guard let id = row.string(0).flatMap(UUID.init(uuidString:)),
              let kind = row.string(1).flatMap(ClipItem.Kind.init(rawValue:)),
              let hash = row.string(9) else { return nil }
        let files = row.string(6)?.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        return ClipItem(id: id, kind: kind, date: Date(timeIntervalSince1970: row.double(2)), text: row.string(3),
                        rtf: row.data(4), imageFile: row.string(5), fileURLs: files, sourceBundleID: row.string(7),
                        sourceName: row.string(8), contentHash: hash, pinned: row.int(10) != 0)
    }
}
