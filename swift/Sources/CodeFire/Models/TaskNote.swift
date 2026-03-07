import Foundation
import GRDB

struct TaskNote: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var taskId: Int64
    var content: String
    var source: String // "manual", "claude", "system"
    var sessionId: String?
    var createdAt: Date
    var updatedAt: Date?
    var mentions: String?  // JSON array of user UUIDs, e.g. '["uuid1","uuid2"]'

    static let databaseTableName = "taskNotes"

    /// Decoded mention UUIDs from the JSON string.
    var mentionIds: [String] {
        guard let mentions, let data = mentions.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }

    /// Encode an array of user UUIDs into the mentions JSON string.
    mutating func setMentions(_ ids: [String]) {
        if ids.isEmpty {
            mentions = nil
        } else if let data = try? JSONEncoder().encode(ids) {
            mentions = String(data: data, encoding: .utf8)
        }
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
