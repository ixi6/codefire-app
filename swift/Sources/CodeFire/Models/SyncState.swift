import Foundation
import GRDB

struct SyncState: Codable, FetchableRecord, PersistableRecord {
    var entityType: String   // "task", "note", "taskNote"
    var localId: String
    var remoteId: String?
    var projectId: String?
    var lastSyncedAt: String?
    var dirty: Int
    var isDeleted: Int

    static let databaseTableName = "syncState"

    enum EntityType: String {
        case task = "task"
        case note = "note"
        case taskNote = "taskNote"
    }

    // MARK: - Convenience

    static func register(
        entityType: EntityType,
        localId: Int64,
        projectId: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO syncState (entityType, localId, projectId, dirty, isDeleted)
                VALUES (?, CAST(? AS TEXT), ?, 1, 0)
            """,
            arguments: [entityType.rawValue, localId, projectId]
        )
    }

    static func dirtyRecords(
        projectId: String,
        entityType: EntityType? = nil,
        in db: Database
    ) throws -> [SyncState] {
        var sql = "SELECT * FROM syncState WHERE dirty = 1 AND projectId = ?"
        var args: [DatabaseValueConvertible] = [projectId]
        if let type = entityType {
            sql += " AND entityType = ?"
            args.append(type.rawValue)
        }
        return try SyncState.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }

    static func markSynced(
        entityType: EntityType,
        localId: Int64,
        remoteId: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE syncState
                SET dirty = 0, remoteId = ?, lastSyncedAt = CURRENT_TIMESTAMP
                WHERE entityType = ? AND localId = CAST(? AS TEXT)
            """,
            arguments: [remoteId, entityType.rawValue, localId]
        )
    }

    static func purgeDeleted(
        entityType: EntityType,
        localId: Int64,
        in db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM syncState WHERE entityType = ? AND localId = CAST(? AS TEXT) AND isDeleted = 1",
            arguments: [entityType.rawValue, localId]
        )
    }

    static func localId(
        forRemoteId remoteId: String,
        entityType: EntityType,
        in db: Database
    ) throws -> Int64? {
        try Int64.fetchOne(
            db,
            sql: "SELECT CAST(localId AS INTEGER) FROM syncState WHERE remoteId = ? AND entityType = ?",
            arguments: [remoteId, entityType.rawValue]
        )
    }

    static func remoteId(
        forLocalId localId: Int64,
        entityType: EntityType,
        in db: Database
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT remoteId FROM syncState WHERE localId = CAST(? AS TEXT) AND entityType = ?",
            arguments: [localId, entityType.rawValue]
        )
    }
}
