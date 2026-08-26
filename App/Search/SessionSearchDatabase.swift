import Foundation
import SQLite3

enum SessionSearchDatabaseErrorKind: Equatable, Sendable {
    case incompatibleSchema
    case sqlite(extendedCode: Int32)
    case other
}

struct SessionSearchDatabaseError: Error, LocalizedError, Sendable {
    let operation: String
    let message: String
    let kind: SessionSearchDatabaseErrorKind

    init(
        operation: String,
        message: String,
        kind: SessionSearchDatabaseErrorKind = .other
    ) {
        self.operation = operation
        self.message = message
        self.kind = kind
    }

    var sqliteExtendedCode: Int32? {
        guard case .sqlite(let extendedCode) = kind else { return nil }
        return extendedCode
    }

    var canResetDerivedIndex: Bool {
        switch kind {
        case .incompatibleSchema:
            return true
        case .sqlite(let extendedCode):
            let primaryCode = extendedCode & 0xFF
            return primaryCode == SQLITE_CORRUPT || primaryCode == SQLITE_NOTADB
        case .other:
            return false
        }
    }

    var errorDescription: String? {
        "[SearchIndex:\(operation)] Database operation failed — \(message)"
    }
}

final class SessionSearchDatabase {
    static let schemaVersion = 1

    private let databaseURL: URL
    private var connection: OpaquePointer?

    init(url: URL) throws {
        databaseURL = url
        let directoryURL = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path)
        } catch {
            throw SessionSearchDatabaseError(
                operation: "prepare directory",
                message: error.localizedDescription)
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            let extendedCode = database.map(sqlite3_extended_errcode) ?? openResult
            sqlite3_close_v2(database)
            throw SessionSearchDatabaseError(
                operation: "open",
                message: message,
                kind: .sqlite(extendedCode: extendedCode))
        }
        connection = database

        guard sqlite3_extended_result_codes(database, 1) == SQLITE_OK else {
            let error = databaseError(operation: "enable extended result codes")
            sqlite3_close_v2(connection)
            connection = nil
            throw error
        }

        do {
            try hardenIndexFiles(operation: "configure database files")
        } catch {
            sqlite3_close_v2(connection)
            connection = nil
            throw error
        }

        do {
            try execute("PRAGMA journal_mode=WAL", operation: "enable WAL")
            try hardenIndexFiles(operation: "configure WAL files")
            try execute("PRAGMA synchronous=NORMAL", operation: "set synchronous mode")
            try prepareSchema()
        } catch {
            sqlite3_close_v2(connection)
            connection = nil
            throw error
        }
    }

    deinit {
        sqlite3_close_v2(connection)
    }

    func fingerprints() throws -> [String: SessionSearchFingerprint] {
        try withStatement(
            "SELECT path, modified, size_bytes FROM indexed_session",
            operation: "read fingerprints") { statement in
            var values: [String: SessionSearchFingerprint] = [:]
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let path = try text(at: 0, in: statement, operation: "read fingerprints")
                    values[path] = SessionSearchFingerprint(
                        path: path,
                        modified: sqlite3_column_double(statement, 1),
                        sizeBytes: Int(sqlite3_column_int64(statement, 2)))
                case SQLITE_DONE:
                    return values
                default:
                    throw databaseError(operation: "read fingerprints")
                }
            }
        }
    }

    func replace(
        fingerprint: SessionSearchFingerprint,
        documents: [SessionSearchDocument]
    ) throws {
        guard documents.allSatisfy({ $0.sessionPath == fingerprint.path }) else {
            throw SessionSearchDatabaseError(
                operation: "replace session",
                message: "Document path does not match its session fingerprint")
        }

        try transaction(operation: "replace session") {
            try deleteDocuments(sessionPath: fingerprint.path, operation: "replace session documents")
            try withStatement(
                "INSERT OR REPLACE INTO indexed_session(path, modified, size_bytes) VALUES (?, ?, ?)",
                operation: "replace session fingerprint") { statement in
                try bind(fingerprint.path, at: 1, in: statement, operation: "replace session fingerprint")
                try bind(fingerprint.modified, at: 2, in: statement, operation: "replace session fingerprint")
                try bind(fingerprint.sizeBytes, at: 3, in: statement, operation: "replace session fingerprint")
                try stepToCompletion(statement, operation: "replace session fingerprint")
            }

            try insert(documents)
        }
    }

    func remove(sessionPaths: Set<String>) throws {
        guard !sessionPaths.isEmpty else { return }
        try transaction(operation: "remove sessions") {
            for path in sessionPaths {
                try deleteDocuments(sessionPath: path, operation: "remove session documents")
                try withStatement(
                    "DELETE FROM indexed_session WHERE path = ?",
                    operation: "remove session fingerprint") { statement in
                    try bind(path, at: 1, in: statement, operation: "remove session fingerprint")
                    try stepToCompletion(statement, operation: "remove session fingerprint")
                }
            }
        }
    }

    func search(normalizedQuery: String, limit: Int) throws -> [SearchResult] {
        guard !normalizedQuery.isEmpty, limit > 0 else { return [] }
        let predicate: String
        let boundQuery: String
        if normalizedQuery.count >= 3 {
            predicate = "search_document MATCH ?"
            let escapedQuery = normalizedQuery.replacingOccurrences(of: "\"", with: "\"\"")
            boundQuery = "\"\(escapedQuery)\""
        } else {
            predicate = "instr(normalized_text, ?) > 0"
            boundQuery = normalizedQuery
        }

        let sql = """
        SELECT session_path, entry_id, project_path, title, excerpt, result_kind
        FROM search_document
        WHERE \(predicate)
        ORDER BY CAST(session_modified AS REAL) DESC, CAST(entry_order AS INTEGER) ASC
        LIMIT ?
        """
        return try withStatement(sql, operation: "search") { statement in
            try bind(boundQuery, at: 1, in: statement, operation: "search")
            try bind(limit, at: 2, in: statement, operation: "search")
            var results: [SearchResult] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let kindValue = try text(at: 5, in: statement, operation: "search")
                    guard let kind = SearchResultKind(rawValue: kindValue) else {
                        throw SessionSearchDatabaseError(
                            operation: "search",
                            message: "Stored result kind is invalid")
                    }
                    results.append(SearchResult(
                        sessionPath: try text(at: 0, in: statement, operation: "search"),
                        entryID: optionalText(at: 1, in: statement),
                        projectPath: try text(at: 2, in: statement, operation: "search"),
                        title: try text(at: 3, in: statement, operation: "search"),
                        excerpt: try text(at: 4, in: statement, operation: "search"),
                        kind: kind))
                case SQLITE_DONE:
                    return results
                default:
                    throw databaseError(operation: "search")
                }
            }
        }
    }

    private func prepareSchema() throws {
        let version: Int = try withStatement("PRAGMA user_version", operation: "read schema version") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw databaseError(operation: "read schema version")
            }
            return Int(sqlite3_column_int(statement, 0))
        }
        guard version == 0 || version == Self.schemaVersion else {
            throw SessionSearchDatabaseError(
                operation: "validate schema version",
                message: "Expected version \(Self.schemaVersion), found \(version)",
                kind: .incompatibleSchema)
        }
        guard version == 0 else {
            try hardenIndexFiles(operation: "configure database files")
            return
        }

        try transaction(operation: "create schema") {
            try execute(
                """
                CREATE TABLE indexed_session (
                    path TEXT PRIMARY KEY NOT NULL,
                    modified REAL NOT NULL,
                    size_bytes INTEGER NOT NULL
                )
                """,
                operation: "create indexed session table")
            try execute(
                """
                CREATE VIRTUAL TABLE search_document USING fts5(
                    session_path UNINDEXED,
                    entry_id UNINDEXED,
                    project_path UNINDEXED,
                    title UNINDEXED,
                    excerpt UNINDEXED,
                    result_kind UNINDEXED,
                    session_modified UNINDEXED,
                    entry_order UNINDEXED,
                    normalized_text,
                    tokenize = 'trigram remove_diacritics 1'
                )
                """,
                operation: "create search document table")
            try execute("PRAGMA user_version = 1", operation: "write schema version")
        }
    }

    private func insert(_ documents: [SessionSearchDocument]) throws {
        guard !documents.isEmpty else { return }
        let sql = """
        INSERT INTO search_document(
            session_path, entry_id, project_path, title, excerpt, result_kind,
            session_modified, entry_order, normalized_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        try withStatement(sql, operation: "insert search document") { statement in
            for (index, document) in documents.enumerated() {
                try bind(document.sessionPath, at: 1, in: statement, operation: "insert search document")
                try bind(document.entryID, at: 2, in: statement, operation: "insert search document")
                try bind(document.projectPath, at: 3, in: statement, operation: "insert search document")
                try bind(document.title, at: 4, in: statement, operation: "insert search document")
                try bind(document.excerpt, at: 5, in: statement, operation: "insert search document")
                try bind(document.kind.rawValue, at: 6, in: statement, operation: "insert search document")
                try bind(document.sessionModified, at: 7, in: statement, operation: "insert search document")
                try bind(document.entryOrder, at: 8, in: statement, operation: "insert search document")
                try bind(document.normalizedText, at: 9, in: statement, operation: "insert search document")
                try stepToCompletion(statement, operation: "insert search document")
                if index < documents.index(before: documents.endIndex) {
                    try reset(statement, operation: "reset search document insert")
                }
            }
        }
    }

    private func deleteDocuments(sessionPath: String, operation: String) throws {
        try withStatement(
            "DELETE FROM search_document WHERE session_path = ?",
            operation: operation) { statement in
            try bind(sessionPath, at: 1, in: statement, operation: operation)
            try stepToCompletion(statement, operation: operation)
        }
    }

    private func transaction(operation: String, body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE", operation: "begin \(operation)")
        do {
            try body()
            try hardenIndexFiles(operation: "harden \(operation)")
            try execute("COMMIT", operation: "commit \(operation)")
        } catch {
            try? execute("ROLLBACK", operation: "rollback \(operation)")
            throw error
        }
    }

    private func execute(_ sql: String, operation: String) throws {
        try withStatement(sql, operation: operation) { statement in
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    continue
                case SQLITE_DONE:
                    return
                default:
                    throw databaseError(operation: operation)
                }
            }
        }
    }

    private func withStatement<T>(
        _ sql: String,
        operation: String,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let connection else {
            throw SessionSearchDatabaseError(operation: operation, message: "Database is closed")
        }
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw databaseError(operation: operation)
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ value: String?, at index: Int32, in statement: OpaquePointer, operation: String) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw databaseError(operation: operation) }
    }

    private func bind(_ value: TimeInterval, at index: Int32, in statement: OpaquePointer, operation: String) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw databaseError(operation: operation)
        }
    }

    private func bind(_ value: Int, at index: Int32, in statement: OpaquePointer, operation: String) throws {
        guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else {
            throw databaseError(operation: operation)
        }
    }

    private func stepToCompletion(_ statement: OpaquePointer, operation: String) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(operation: operation)
        }
    }

    private func reset(_ statement: OpaquePointer, operation: String) throws {
        guard sqlite3_reset(statement) == SQLITE_OK else {
            throw databaseError(operation: operation)
        }
        guard sqlite3_clear_bindings(statement) == SQLITE_OK else {
            throw databaseError(operation: operation)
        }
    }

    private func hardenIndexFiles(operation: String) throws {
        try hardenIndexFile(databaseURL, label: "database", isRequired: true, operation: operation)
        try hardenIndexFile(
            URL(filePath: databaseURL.path + "-wal"),
            label: "write-ahead log",
            isRequired: false,
            operation: operation)
        try hardenIndexFile(
            URL(filePath: databaseURL.path + "-shm"),
            label: "shared memory",
            isRequired: false,
            operation: operation)
    }

    private func hardenIndexFile(
        _ url: URL,
        label: String,
        isRequired: Bool,
        operation: String
    ) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            guard isRequired else { return }
            throw SessionSearchDatabaseError(
                operation: operation,
                message: "The \(label) file is missing")
        }

        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path)
            var excludedURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try excludedURL.setResourceValues(resourceValues)
        } catch {
            if !isRequired, !fileManager.fileExists(atPath: url.path) { return }
            throw SessionSearchDatabaseError(
                operation: operation,
                message: "Unable to secure the \(label) file — \(error.localizedDescription)")
        }
    }

    private func text(at index: Int32, in statement: OpaquePointer, operation: String) throws -> String {
        guard let value = optionalText(at: index, in: statement) else {
            throw SessionSearchDatabaseError(operation: operation, message: "Stored text value is missing")
        }
        return value
    }

    private func optionalText(at index: Int32, in statement: OpaquePointer) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let bytes = sqlite3_column_text(statement, index)
        else { return nil }
        let characters = UnsafeRawPointer(bytes).assumingMemoryBound(to: CChar.self)
        return String(cString: characters)
    }

    private func databaseError(operation: String) -> SessionSearchDatabaseError {
        guard let connection else {
            return SessionSearchDatabaseError(operation: operation, message: "Database is closed")
        }
        return SessionSearchDatabaseError(
            operation: operation,
            message: String(cString: sqlite3_errmsg(connection)),
            kind: .sqlite(extendedCode: sqlite3_extended_errcode(connection)))
    }
}

private var sqliteTransient: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
