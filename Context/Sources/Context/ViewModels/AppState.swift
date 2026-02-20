import Foundation
import GRDB
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var currentProject: Project?
    @Published var projects: [Project] = []
    @Published var selectedTab: GUITab = .tasks

    enum GUITab: String, CaseIterable {
        case tasks = "Tasks"
        case dashboard = "Dashboard"
        case sessions = "Sessions"
        case notes = "Notes"
        case memory = "Memory"
        case rules = "Rules"
        case visualize = "Visualize"

        var icon: String {
            switch self {
            case .dashboard: return "house"
            case .sessions: return "clock"
            case .tasks: return "checklist"
            case .notes: return "note.text"
            case .memory: return "brain"
            case .rules: return "doc.text.magnifyingglass"
            case .visualize: return "chart.dots.scatter"
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

            // Auto-select the most recently opened project if none is selected.
            if currentProject == nil, let first = projects.first {
                selectProject(first)
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

            // Notify views that session data is available.
            NotificationCenter.default.post(name: .sessionsDidChange, object: nil)
        } catch {
            print("Failed to update project: \(error)")
        }
    }
}
