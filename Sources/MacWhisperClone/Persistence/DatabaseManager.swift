import Foundation
import GRDB

// MARK: - Database Manager

/// Manages SQLite database persistence for transcription sessions using GRDB.
final class DatabaseManager: ObservableObject {

    static let shared = DatabaseManager()

    private let dbPool: DatabasePool

    // MARK: Initialization

    private init() {
        do {
            dbPool = try DatabasePool(path: AppPaths.databasePath.path)
            try migrate()
            Logger.info("Database initialized at \(AppPaths.databasePath.path)")
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    // MARK: - Migration

    private func migrate() throws {
        try dbPool.write { db in
            // Transcription sessions table
            try db.create(table: "transcriptionSession", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("audioFileName", .text).notNull()
                t.column("audioFilePath", .text).notNull()
                t.column("modelID", .text).notNull()
                t.column("engineType", .text).notNull()
                t.column("detectedLanguage", .text).notNull()
                t.column("audioDuration", .double).notNull()
                t.column("processingTime", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("fullText", .text).notNull()
            }

            // Segments table
            try db.create(table: "transcriptionSegment", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sessionUUID", .text).notNull()
                    .references("transcriptionSession", onDelete: .cascade)
                t.column("segmentIndex", .integer).notNull()
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("text", .text).notNull()
                t.column("speaker", .text)
            }

            // Index for faster lookups
            try db.create(index: "idx_segment_session", on: "transcriptionSegment", columns: ["sessionUUID"], ifNotExists: true)
        }
    }

    // MARK: - Save Session

    /// Save a transcription session with all its segments.
    func saveSession(
        audioFile: AudioFile,
        result: TranscriptionResult
    ) throws -> UUID {
        let sessionUUID = UUID()

        try dbPool.write { db in
            // Insert session
            var session = TranscriptionSessionRecord(
                uuid: sessionUUID.uuidString,
                audioFileName: audioFile.name,
                audioFilePath: audioFile.url.path,
                modelID: result.modelUsed,
                engineType: result.engineUsed.rawValue,
                detectedLanguage: result.detectedLanguage,
                audioDuration: result.audioDuration,
                processingTime: result.processingTime,
                createdAt: Date(),
                fullText: result.fullText
            )
            try session.insert(db)

            // Insert segments
            for segment in result.segments {
                var record = TranscriptionSegmentRecord(
                    sessionUUID: sessionUUID.uuidString,
                    segmentIndex: segment.index,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    text: segment.text,
                    speaker: segment.speaker
                )
                try record.insert(db)
            }
        }

        Logger.info("Saved transcription session: \(sessionUUID)")
        return sessionUUID
    }

    // MARK: - Load Sessions

    /// Load all saved transcription sessions (without segments).
    func loadAllSessions() throws -> [TranscriptionSessionRecord] {
        try dbPool.read { db in
            try TranscriptionSessionRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    /// Load segments for a specific session.
    func loadSegments(for sessionUUID: String) throws -> [TranscriptionSegmentRecord] {
        try dbPool.read { db in
            try TranscriptionSegmentRecord
                .filter(Column("sessionUUID") == sessionUUID)
                .order(Column("segmentIndex").asc)
                .fetchAll(db)
        }
    }

    /// Load a full session with segments.
    func loadSession(withUUID uuid: String) throws -> (TranscriptionSessionRecord, [TranscriptionSegmentRecord])? {
        try dbPool.read { db in
            guard let session = try TranscriptionSessionRecord
                .filter(Column("uuid") == uuid)
                .fetchOne(db) else {
                return nil
            }

            let segments = try TranscriptionSegmentRecord
                .filter(Column("sessionUUID") == uuid)
                .order(Column("segmentIndex").asc)
                .fetchAll(db)

            return (session, segments)
        }
    }

    // MARK: - Delete Session

    /// Delete a transcription session and all its segments.
    func deleteSession(uuid: String) throws {
        try dbPool.write { db in
            try TranscriptionSessionRecord
                .filter(Column("uuid") == uuid)
                .deleteAll(db)
            // Segments are cascade-deleted
        }
        Logger.info("Deleted session: \(uuid)")
    }

    // MARK: - Search

    /// Search sessions by text content.
    func searchSessions(query: String) throws -> [TranscriptionSessionRecord] {
        try dbPool.read { db in
            try TranscriptionSessionRecord
                .filter(Column("fullText").like("%\(query)%"))
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }
}

// MARK: - Database Records

/// Database record for a transcription session.
struct TranscriptionSessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptionSession"

    var id: Int64?
    var uuid: String
    var audioFileName: String
    var audioFilePath: String
    var modelID: String
    var engineType: String
    var detectedLanguage: String
    var audioDuration: Double
    var processingTime: Double
    var createdAt: Date
    var fullText: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Database record for a transcription segment.
struct TranscriptionSegmentRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptionSegment"

    var id: Int64?
    var sessionUUID: String
    var segmentIndex: Int
    var startTime: Double
    var endTime: Double
    var text: String
    var speaker: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
