import Foundation
import GRDB

struct Project: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: String // UUID string
    var name: String
    var path: String
    var claudeProject: String? // ~/.claude/projects/<key> path
    var lastOpened: Date?
    var createdAt: Date

    static let databaseTableName = "projects"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let path = Column(CodingKeys.path)
        static let claudeProject = Column(CodingKeys.claudeProject)
        static let lastOpened = Column(CodingKeys.lastOpened)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
