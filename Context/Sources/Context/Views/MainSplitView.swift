import SwiftUI

struct MainSplitView: View {
    @EnvironmentObject var appState: AppState
    @State private var projectPath: String = ""

    var body: some View {
        HSplitView {
            TerminalTabView(projectPath: $projectPath)
                .frame(minWidth: 400, idealWidth: 700)
            GUIPanelView()
                .frame(minWidth: 400, idealWidth: 700)
        }
        .onChange(of: appState.currentProject) { _, project in
            if let project = project {
                projectPath = project.path
            }
        }
    }
}
