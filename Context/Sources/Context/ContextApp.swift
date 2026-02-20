import SwiftUI

@main
struct ContextApp: App {
    @StateObject private var appState = AppState()

    init() {
        do {
            try DatabaseService.shared.setup()
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .environmentObject(appState)
                .onAppear {
                    appState.loadProjects()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1400, height: 900)
    }
}
