import Foundation
import GRDB

// Named TaskItem to avoid conflict with Swift's Task
struct TaskItem: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var projectId: String
    var title: String
    var description: String?
    var status: String // "todo", "in_progress", "done"
    var priority: Int
    var sourceSession: String?
    var source: String // "claude" or "manual"
    var createdAt: Date
    var completedAt: Date?

    static let databaseTableName = "taskItems"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
