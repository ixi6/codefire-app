import SwiftUI

/// A text field that shows a team member autocomplete popover when the user types `@`.
/// Tracks resolved mention UUIDs for syncing to Supabase.
struct MentionTextField: View {
    @Binding var text: String
    @Binding var mentionedUserIds: [String]
    let placeholder: String
    let onSubmit: () -> Void

    @StateObject private var premium = PremiumService.shared
    @State private var showSuggestions = false
    @State private var suggestionFilter = ""
    @State private var teamMembers: [TeamMember] = []
    @State private var mentionStartIndex: String.Index?

    private var filteredMembers: [TeamMember] {
        let query = suggestionFilter.lowercased()
        if query.isEmpty { return teamMembers }
        return teamMembers.filter {
            ($0.user?.displayName.lowercased().contains(query) ?? false) ||
            ($0.user?.email.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onChange(of: text) { _, newValue in
                        handleTextChange(newValue)
                    }
                    .onSubmit {
                        if showSuggestions, let first = filteredMembers.first {
                            insertMention(first)
                        } else {
                            onSubmit()
                        }
                    }

                Button {
                    onSubmit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(text.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if showSuggestions && !filteredMembers.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredMembers.prefix(5), id: \.userId) { member in
                        Button {
                            insertMention(member)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Text(memberInitial(member))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.user?.displayName ?? "Unknown")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(member.user?.email ?? "")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.clear)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                )
                .padding(.top, 2)
            }
        }
        .task {
            await loadTeamMembers()
        }
    }

    private func handleTextChange(_ newValue: String) {
        // Find the last `@` that might be an in-progress mention
        guard let atIndex = newValue.lastIndex(of: "@") else {
            showSuggestions = false
            mentionStartIndex = nil
            return
        }

        let afterAt = newValue[newValue.index(after: atIndex)...]

        // If there's a space after partial text, the mention is "closed"
        if afterAt.contains(" ") && afterAt.count > 1 {
            // Check if this is a completed mention or abandoned
            showSuggestions = false
            mentionStartIndex = nil
            return
        }

        mentionStartIndex = atIndex
        suggestionFilter = String(afterAt)
        showSuggestions = true
    }

    private func insertMention(_ member: TeamMember) {
        guard let startIndex = mentionStartIndex else { return }

        let displayName = member.user?.displayName ?? "Unknown"
        let before = String(text[text.startIndex..<startIndex])
        let replacement = "@\(displayName) "
        text = before + replacement

        if let userId = member.user?.id, !mentionedUserIds.contains(userId) {
            mentionedUserIds.append(userId)
        }

        showSuggestions = false
        mentionStartIndex = nil
    }

    private func memberInitial(_ member: TeamMember) -> String {
        let name = member.user?.displayName ?? ""
        return String(name.prefix(1)).uppercased()
    }

    private func loadTeamMembers() async {
        guard let teamId = premium.status.team?.id else { return }
        do {
            teamMembers = try await premium.listMembers(teamId: teamId)
        } catch {
            print("MentionTextField: failed to load team members: \(error)")
        }
    }
}
