import SwiftUI

/// Shown as a sheet when a session ends and cloud sync is enabled.
/// Prompts the user to share the session summary with their team.
struct SessionSharePromptView: View {
    let sessionId: String
    let slug: String?
    let model: String?
    let gitBranch: String?
    let filesChanged: [String]
    let startedAt: Date?
    let durationMins: Int?

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var claudeService: ClaudeService
    @State private var summary: String = ""
    @State private var isGenerating = false
    @State private var isSharing = false
    @State private var shared = false
    @State private var error: String?

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                Text("Share Session with Team?")
                    .font(.system(size: 15, weight: .semibold))
            }

            // Session info
            HStack(spacing: 12) {
                if let branch = gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.purple)
                }
                if let model {
                    Text(model)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if let mins = durationMins {
                    Text("\(mins) min")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // Summary editor
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating summary...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                TextEditor(text: $summary)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100, maxHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                    )
            }

            if !filesChanged.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 9))
                    Text("\(filesChanged.count) files changed")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Skip") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if shared {
                    Label("Shared!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    Button {
                        shareSession()
                    } label: {
                        HStack(spacing: 4) {
                            if isSharing {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Share with Team")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty || isSharing || isGenerating)
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 360)
        .task {
            await generateSummary()
        }
    }

    private func generateSummary() async {
        guard let project = appState.currentProject,
              let claudeDir = project.claudeProject else {
            summary = "Session completed."
            return
        }

        isGenerating = true
        if let result = await claudeService.generateSessionSummary(
            sessionId: sessionId,
            claudeProjectPath: claudeDir
        ) {
            summary = result
        } else {
            summary = "Session completed on \(gitBranch ?? "unknown branch")."
        }
        isGenerating = false
    }

    private func shareSession() {
        guard let projectId = appState.currentProject?.id else { return }
        isSharing = true
        error = nil

        // Find the remote project ID for this local project
        Task {
            let premium = PremiumService.shared

            // Build a SessionSummary to share
            let toShare = SessionSummary(
                id: "",  // Server generates
                projectId: projectId,
                userId: premium.status.user?.id ?? "",
                sessionSlug: slug,
                model: model,
                gitBranch: gitBranch,
                summary: summary,
                filesChanged: filesChanged,
                durationMins: durationMins,
                startedAt: startedAt.map { ISO8601DateFormatter().string(from: $0) },
                endedAt: ISO8601DateFormatter().string(from: Date()),
                sharedAt: ISO8601DateFormatter().string(from: Date()),
                user: nil
            )

            do {
                _ = try await premium.shareSessionSummary(toShare)
                shared = true
                // Auto-dismiss after a moment
                try? await Task.sleep(for: .seconds(1.5))
                onDismiss()
            } catch {
                self.error = "Failed to share: \(error.localizedDescription)"
            }
            isSharing = false
        }
    }
}
