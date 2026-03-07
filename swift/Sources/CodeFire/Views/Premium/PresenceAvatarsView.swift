import SwiftUI

struct PresenceAvatarsView: View {
    @ObservedObject var premiumService = PremiumService.shared
    @ObservedObject var syncEngine = SyncEngine.shared
    let projectId: String?

    @State private var presenceEntries: [RealtimeClient.PresenceEntry] = []
    @State private var presenceClient: RealtimeClient?

    var body: some View {
        Group {
            if !premiumService.status.enabled || !premiumService.status.authenticated {
                EmptyView()
            } else if presenceEntries.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: -6) {
                    ForEach(presenceEntries.prefix(5), id: \.userId) { entry in
                        memberAvatar(entry)
                    }

                    if presenceEntries.count > 5 {
                        Text("+\(presenceEntries.count - 5)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .overlay(
                                        Circle()
                                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                                    )
                            )
                    }
                }
            }
        }
        .task {
            await connectPresence()
        }
        .onDisappear {
            disconnectPresence()
        }
    }

    private func memberAvatar(_ entry: RealtimeClient.PresenceEntry) -> some View {
        let initials = String(entry.displayName.prefix(2).uppercased())

        return ZStack {
            Circle()
                .fill(colorForUser(entry.userId))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                )

            Text(initials)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)

            // Online indicator dot
            Circle()
                .fill(entry.status == "active" ? Color.green : Color.yellow)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                )
                .offset(x: 7, y: 7)
        }
        .help(tooltipText(entry))
    }

    private func tooltipText(_ entry: RealtimeClient.PresenceEntry) -> String {
        var parts = [entry.displayName]
        if entry.status == "idle" { parts.append("(idle)") }
        if let file = entry.activeFile { parts.append("editing \(file)") }
        if let branch = entry.gitBranch { parts.append("on \(branch)") }
        return parts.joined(separator: " — ")
    }

    private func connectPresence() async {
        guard let projectId,
              premiumService.status.enabled,
              premiumService.status.authenticated else { return }

        let client = RealtimeClient(
            supabaseUrl: premiumService.supabaseBaseURL,
            anonKey: premiumService.supabaseAnonKeyValue
        )

        let userState: [String: Any] = [
            "user_id": premiumService.status.user?.id ?? "",
            "display_name": premiumService.status.user?.displayName ?? "Unknown",
            "status": "active",
        ]

        let channel = "presence:project-\(projectId)"
        client.joinPresence(channel: channel, userState: userState) { entries in
            // Filter out self and update
            let currentUserId = premiumService.status.user?.id
            presenceEntries = Array(entries.values)
                .filter { $0.userId != currentUserId }
                .sorted { $0.displayName < $1.displayName }
        }

        client.connect(accessToken: premiumService.currentAccessToken)
        presenceClient = client
    }

    private func disconnectPresence() {
        presenceClient?.disconnect()
        presenceClient = nil
        presenceEntries = []
    }

    private func colorForUser(_ id: String) -> Color {
        let hash = abs(id.hashValue)
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan, .indigo, .mint]
        return colors[hash % colors.count]
    }
}
