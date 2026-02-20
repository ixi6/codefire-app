import Foundation
import GRDB

class DatabaseService {
    static let shared = DatabaseService()
    private(set) var dbQueue: DatabaseQueue!

    private init() {}

    func setup() throws {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Context", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        let dbPath = appSupportURL.appendingPathComponent("context.db").path
        dbQueue = try DatabaseQueue(path: dbPath)

        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createTables") { db in
            try db.create(table: "projects") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("path", .text).notNull().unique()
                t.column("claudeProject", .text)
                t.column("lastOpened", .datetime)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("slug", .text)
                t.column("startedAt", .datetime)
                t.column("endedAt", .datetime)
                t.column("model", .text)
                t.column("gitBranch", .text)
                t.column("summary", .text)
                t.column("messageCount", .integer).notNull().defaults(to: 0)
                t.column("toolUseCount", .integer).notNull().defaults(to: 0)
                t.column("filesChanged", .text)
            }

            try db.create(table: "codebaseSnapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("projectId", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("capturedAt", .datetime).notNull()
                t.column("fileTree", .text)
                t.column("schemaHash", .text)
                t.column("keySymbols", .text)
            }

            try db.create(table: "notes") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("projectId", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("sessionId", .text)
                    .references("sessions", onDelete: .setNull)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "patterns") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("projectId", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("category", .text).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text).notNull()
                t.column("sourceSession", .text)
                    .references("sessions", onDelete: .setNull)
                t.column("autoDetected", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "taskItems") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("projectId", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("status", .text).notNull().defaults(to: "todo")
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("sourceSession", .text)
                    .references("sessions", onDelete: .setNull)
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }
        }

        migrator.registerMigration("v1_createFTS") { db in
            // Full-text search on sessions
            try db.create(virtualTable: "sessionsFts", using: FTS5()) { t in
                t.synchronize(withTable: "sessions")
                t.column("summary")
            }

            // Full-text search on notes
            try db.create(virtualTable: "notesFts", using: FTS5()) { t in
                t.synchronize(withTable: "notes")
                t.column("title")
                t.column("content")
            }
        }

        return migrator
    }
}
