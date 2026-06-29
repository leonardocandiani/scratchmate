import Foundation
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to copy the string buffer when binding,
/// needed because Swift's bridged C strings are temporary.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let m): return "Failed to open the database: \(m)"
        case .prepareFailed(let m): return "Failed to prepare statement: \(m)"
        case .stepFailed(let m): return "Failed to run statement: \(m)"
        }
    }
}

/// Local SQLite storage for the notes. No external dependency: uses the system
/// libsqlite3. Local persistence by default, in line with the plan's "all local".
public final class Database {
    private var db: OpaquePointer?
    public let path: String

    /// Opens (or creates) the database at the given path. Use ":memory:" for an ephemeral test database.
    public init(path: String) throws {
        self.path = path
        if path != ":memory:" {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true
            )
        }
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            // sqlite3_open can allocate a handle even on failure; close it so the
            // throwing init does not leak the connection (deinit never runs on a
            // failed init).
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw DatabaseError.openFailed(msg)
        }
        // Hardens local persistence: waits instead of failing on a transient lock,
        // and WAL for concurrent read/write (no-op for :memory:).
        sqlite3_busy_timeout(db, 5000)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        do {
            try migrate()
        } catch {
            // The connection above is live; close it before rethrowing so the failed
            // init leaves no dangling handle.
            sqlite3_close(db)
            db = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Default database path in the user's Application Support.
    public static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScratchMate/scratchmate.sqlite").path
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL DEFAULT '',
            content TEXT NOT NULL DEFAULT '',
            language_id TEXT NOT NULL DEFAULT 'markdown',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            slot INTEGER,
            expires_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated_at DESC);
        CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_slot ON notes(slot) WHERE slot IS NOT NULL;
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - CRUD

    /// Inserts a note and returns the version with the assigned id.
    @discardableResult
    public func insert(_ note: Note) throws -> Note {
        let sql = """
        INSERT INTO notes (title, content, language_id, created_at, updated_at, slot, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, note.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, note.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, note.languageId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 5, note.updatedAt.timeIntervalSince1970)
        bindOptionalInt(stmt, 6, note.slot)
        bindOptionalDouble(stmt, 7, note.expiresAt?.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        var result = note
        result.id = sqlite3_last_insert_rowid(db)
        return result
    }

    /// Updates title, content, language, slot, expiration and updated_at.
    public func update(_ note: Note) throws {
        let sql = """
        UPDATE notes SET title = ?, content = ?, language_id = ?, updated_at = ?,
            slot = ?, expires_at = ? WHERE id = ?;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, note.title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, note.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, note.languageId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 4, note.updatedAt.timeIntervalSince1970)
        bindOptionalInt(stmt, 5, note.slot)
        bindOptionalDouble(stmt, 6, note.expiresAt?.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 7, note.id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func delete(id: Int64) throws {
        let stmt = try prepare("DELETE FROM notes WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Fetches a note by id.
    public func note(id: Int64) throws -> Note? {
        let stmt = try prepare("SELECT * FROM notes WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? readRow(stmt) : nil
    }

    /// Lists notes with the most recent first.
    public func recentNotes(limit: Int = 100) throws -> [Note] {
        let stmt = try prepare("SELECT * FROM notes ORDER BY updated_at DESC LIMIT ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        var notes: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            notes.append(readRow(stmt))
        }
        return notes
    }

    /// Searches by substring in title or content (case-insensitive).
    public func search(_ query: String, limit: Int = 50) throws -> [Note] {
        let stmt = try prepare("""
            SELECT * FROM notes WHERE title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\'
            ORDER BY updated_at DESC LIMIT ?;
            """)
        defer { sqlite3_finalize(stmt) }
        // Escapes the LIKE wildcards so "a_b"/"50%" do not become patterns (backslash first).
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(limit))
        var notes: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            notes.append(readRow(stmt))
        }
        return notes
    }

    /// Deletes expired notes (expires_at in the past). Returns how many were removed.
    @discardableResult
    public func purgeExpired(now: Date = Date()) throws -> Int {
        let stmt = try prepare("DELETE FROM notes WHERE expires_at IS NOT NULL AND expires_at < ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, now.timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        return Int(sqlite3_changes(db))
    }

    // MARK: - Internals

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func readRow(_ stmt: OpaquePointer?) -> Note {
        Note(
            id: sqlite3_column_int64(stmt, 0),
            title: columnText(stmt, 1),
            content: columnText(stmt, 2),
            languageId: columnText(stmt, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
            slot: columnOptionalInt(stmt, 6),
            expiresAt: columnOptionalDate(stmt, 7)
        )
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private func columnOptionalInt(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, index))
    }

    private func columnOptionalDate(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
            ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    private func bindOptionalInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int64(stmt, index, Int64(value)) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value { sqlite3_bind_double(stmt, index, value) }
        else { sqlite3_bind_null(stmt, index) }
    }
}
