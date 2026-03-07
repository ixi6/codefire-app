import Foundation
import GRDB

struct SyncState: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var entityType: String   // "task", "note", "task_note"
    var localId: Int64
    var remoteId: String?    // Supabase UUID
    var projectId: String
    var isDirty: Bool
    var isDeleted: Bool
    var lastSyncedAt: Date?
    var syncVersion: Int64

    static let databaseTableName = "syncState"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum EntityType: String {
        case task = "task"
        case note = "note"
        case taskNote = "task_note"
    }

    // MARK: - Convenience

    /// Register a local entity for sync tracking.
    static func register(
        entityType: EntityType,
        localId: Int64,
        projectId: String,
        in db: Database
    ) throws {
        var state = SyncState(
            entityType: entityType.rawValue,
            localId: localId,
            remoteId: nil,
            projectId: projectId,
            isDirty: true,
            isDeleted: false,
            lastSyncedAt: nil,
            syncVersion: 0
        )
        try state.insert(db, onConflict: .ignore)
    }

    /// Fetch all dirty records for a project, optionally filtered by entity type.
    static func dirtyRecords(
        projectId: String,
        entityType: EntityType? = nil,
        in db: Database
    ) throws -> [SyncState] {
        var sql = "SELECT * FROM syncState WHERE isDirty = 1 AND projectId = ?"
        var args: [DatabaseValueConvertible] = [projectId]
        if let type = entityType {
            sql += " AND entityType = ?"
            args.append(type.rawValue)
        }
        return try SyncState.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    }

    /// Mark a record as synced after successful push.
    static func markSynced(
        entityType: EntityType,
        localId: Int64,
        remoteId: String,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
                UPDATE syncState
                SET isDirty = 0, remoteId = ?, lastSyncedAt = CURRENT_TIMESTAMP
                WHERE entityType = ? AND localId = ?
            """,
            arguments: [remoteId, entityType.rawValue, localId]
        )
    }

    /// Remove sync tracking for deleted records that have been confirmed server-side.
    static func purgeDeleted(
        entityType: EntityType,
        localId: Int64,
        in db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM syncState WHERE entityType = ? AND localId = ? AND isDeleted = 1",
            arguments: [entityType.rawValue, localId]
        )
    }

    /// Find the local ID for a known remote UUID.
    static func localId(
        forRemoteId remoteId: String,
        entityType: EntityType,
        in db: Database
    ) throws -> Int64? {
        try Int64.fetchOne(
            db,
            sql: "SELECT localId FROM syncState WHERE remoteId = ? AND entityType = ?",
            arguments: [remoteId, entityType.rawValue]
        )
    }

    /// Find the remote UUID for a known local ID.
    static func remoteId(
        forLocalId localId: Int64,
        entityType: EntityType,
        in db: Database
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT remoteId FROM syncState WHERE localId = ? AND entityType = ?",
            arguments: [localId, entityType.rawValue]
        )
    }
}
