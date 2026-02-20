import Foundation
import GRDB
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var currentProject: Project?
    @Published var projects: [Project] = []
    @Published var selectedTab: GUITab = .dashboard

    enum GUITab: String, CaseIterable {
        case dashboard = "Dashboard"
        case sessions = "Sessions"
        case tasks = "Tasks"
        case notes = "Notes"
        case memory = "Memory"

        var icon: String {
            switch self {
            case .dashboard: return "house"
            case .sessions: return "clock"
            case .tasks: return "checklist"
            case .notes: return "note.text"
            case .memory: return "brain"
            }
        }
    }

    func loadProjects() {
        do {
            let discovery = ProjectDiscovery()
            try discovery.importProjects()
            projects = try DatabaseService.shared.dbQueue.read { db in
                try Project.order(Project.Columns.lastOpened.desc).fetchAll(db)
            }
        } catch {
            print("Failed to load projects: \(error)")
        }
    }

    func selectProject(_ project: Project) {
        currentProject = project
        do {
            try DatabaseService.shared.dbQueue.write { db in
                var updated = project
                updated.lastOpened = Date()
                try updated.update(db)
            }
            let discovery = ProjectDiscovery()
            try discovery.importSessions(for: project)
        } catch {
            print("Failed to update project: \(error)")
        }
    }
}
