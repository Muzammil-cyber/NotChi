import Foundation
import SQLite3

/// Minimal wrapper over the system SQLite library (no third-party dependency).
/// Not thread-safe; each owner uses its connection from one actor.
final class SQLiteDatabase {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw Failure(description: message)
        }
        // WAL: crash-safe, and a write never rewrites the whole file.
        try execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw Failure(description: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure(description: "\(lastError) in: \(sql)")
        }
        return Statement(statement)
    }

    /// Runs `body` in a transaction, rolling back if it throws.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }

    final class Statement {
        private let pointer: OpaquePointer
        /// Tells SQLite to copy bound strings and blobs.
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        fileprivate init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { sqlite3_finalize(pointer) }

        /// Binds values to `?` placeholders in order (1-based in SQLite).
        @discardableResult
        func bind(_ values: Any?...) -> Statement { bind(values: values) }

        @discardableResult
        func bind(values: [Any?]) -> Statement {
            sqlite3_reset(pointer)
            sqlite3_clear_bindings(pointer)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                switch value {
                case nil: sqlite3_bind_null(pointer, index)
                case let v as String: sqlite3_bind_text(pointer, index, v, -1, Self.transient)
                case let v as Int: sqlite3_bind_int64(pointer, index, Int64(v))
                case let v as Bool: sqlite3_bind_int64(pointer, index, v ? 1 : 0)
                case let v as Double: sqlite3_bind_double(pointer, index, v)
                case let v as Data:
                    _ = v.withUnsafeBytes { sqlite3_bind_blob(pointer, index, $0.baseAddress, Int32(v.count), Self.transient) }
                default: sqlite3_bind_null(pointer, index)
                }
            }
            return self
        }

        /// Executes a statement that returns no rows.
        func run() throws {
            let code = sqlite3_step(pointer)
            sqlite3_reset(pointer)
            guard code == SQLITE_DONE || code == SQLITE_ROW else {
                throw Failure(description: String(cString: sqlite3_errmsg(sqlite3_db_handle(pointer))))
            }
        }

        /// Steps through result rows.
        func rows(_ body: (Row) throws -> Void) rethrows {
            defer { sqlite3_reset(pointer) }
            while sqlite3_step(pointer) == SQLITE_ROW { try body(Row(pointer: pointer)) }
        }
    }

    struct Row {
        fileprivate let pointer: OpaquePointer

        func string(_ column: Int32) -> String? {
            guard let text = sqlite3_column_text(pointer, column) else { return nil }
            return String(cString: text)
        }

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(pointer, column)) }

        func double(_ column: Int32) -> Double { sqlite3_column_double(pointer, column) }

        func data(_ column: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(pointer, column) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(pointer, column)))
        }
    }
}
