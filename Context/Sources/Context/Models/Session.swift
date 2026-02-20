import Foundation
import GRDB

struct Session: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: String // Claude's session UUID
    var projectId: String
    var slug: String?
    var startedAt: Date?
    var endedAt: Date?
    var model: String?
    var gitBranch: String?
    var summary: String?
    var messageCount: Int
    var toolUseCount: Int
    var filesChanged: String? // JSON array

    static let databaseTableName = "sessions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let projectId = Column(CodingKeys.projectId)
        static let slug = Column(CodingKeys.slug)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let model = Column(CodingKeys.model)
        static let gitBranch = Column(CodingKeys.gitBranch)
        static let summary = Column(CodingKeys.summary)
        static let messageCount = Column(CodingKeys.messageCount)
        static let toolUseCount = Column(CodingKeys.toolUseCount)
        static let filesChanged = Column(CodingKeys.filesChanged)
    }

    // Convenience: decode files changed as array
    var filesChangedArray: [String] {
        guard let json = filesChanged,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return array
    }
}
