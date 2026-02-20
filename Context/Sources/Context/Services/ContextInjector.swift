import Foundation

// MARK: - Context Injector

/// Manages the integration surface between Context.app and Claude Code.
/// Handles two responsibilities:
/// 1. Injecting/removing a managed section in a project's CLAUDE.md file
/// 2. Writing an MCP configuration file that Claude Code can reference
class ContextInjector {

    enum InjectorError: Error, LocalizedError {
        case projectPathMissing
        case fileOperationFailed(String)

        var errorDescription: String? {
            switch self {
            case .projectPathMissing: return "Project path is empty"
            case .fileOperationFailed(let msg): return "File operation failed: \(msg)"
            }
        }
    }

    /// Markers used to identify the Context.app-managed section in CLAUDE.md
    static let sectionStart = "<!-- Context.app managed section -->"
    static let sectionEnd = "<!-- End Context.app section -->"

    /// The content injected between the markers
    private static let managedContent = """
    # Context
    This project uses Context.app for session memory.
    Use the `context` MCP tools to retrieve project history,
    active tasks, patterns, and codebase structure when needed.
    """

    private let db: DatabaseService
    private let fileManager: FileManager

    init(db: DatabaseService = .shared, fileManager: FileManager = .default) {
        self.db = db
        self.fileManager = fileManager
    }

    // MARK: - CLAUDE.md Management

    /// Add or update the Context.app managed section in the project's CLAUDE.md.
    /// If CLAUDE.md exists, the managed section is found and replaced (or appended).
    /// If CLAUDE.md does not exist, a new file is created with just the managed section.
    func updateClaudeMD(for project: Project) throws {
        let projectPath = project.path
        guard !projectPath.isEmpty else {
            throw InjectorError.projectPathMissing
        }

        let claudeMDPath = (projectPath as NSString).appendingPathComponent("CLAUDE.md")
        let section = buildManagedSection()

        if fileManager.fileExists(atPath: claudeMDPath) {
            var content = try String(contentsOfFile: claudeMDPath, encoding: .utf8)

            if let range = findManagedSectionRange(in: content) {
                // Replace existing section
                content.replaceSubrange(range, with: section)
            } else {
                // Append section
                if !content.hasSuffix("\n") {
                    content += "\n"
                }
                content += "\n" + section + "\n"
            }

            try content.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        } else {
            // Create new CLAUDE.md with just the managed section
            let content = section + "\n"
            try content.write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        }
    }

    /// Remove the Context.app managed section from the project's CLAUDE.md.
    /// If the file becomes empty (or whitespace-only) after removal, delete it.
    func removeClaudeMDSection(for project: Project) throws {
        let projectPath = project.path
        guard !projectPath.isEmpty else {
            throw InjectorError.projectPathMissing
        }

        let claudeMDPath = (projectPath as NSString).appendingPathComponent("CLAUDE.md")

        guard fileManager.fileExists(atPath: claudeMDPath) else {
            return // Nothing to remove
        }

        var content = try String(contentsOfFile: claudeMDPath, encoding: .utf8)

        guard let range = findManagedSectionRange(in: content) else {
            return // Section not found, nothing to do
        }

        content.removeSubrange(range)

        // Clean up extra newlines left behind
        content = content
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if content.isEmpty {
            try fileManager.removeItem(atPath: claudeMDPath)
        } else {
            try (content + "\n").write(toFile: claudeMDPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - MCP Configuration

    /// Write the MCP configuration file that Claude Code can reference.
    /// Creates ~/Library/Application Support/Context/mcp-config.json
    ///
    /// Note: The transport bridge (connecting this config to the in-process MCPServer)
    /// is a future enhancement. For now this writes the structural config.
    func configureMCPConnection() throws {
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Context", isDirectory: true)

        try fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        let configPath = appSupportURL.appendingPathComponent("mcp-config.json")

        let config: [String: Any] = [
            "mcpServers": [
                "context-app": [
                    "command": "context-mcp-bridge",
                    "args": [] as [String],
                    "description": "Context.app - Session memory and project intelligence for Claude Code"
                ]
            ]
        ]

        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configPath, options: .atomic)
    }

    // MARK: - Helpers

    /// Build the full managed section string including markers.
    private func buildManagedSection() -> String {
        return [
            Self.sectionStart,
            Self.managedContent,
            Self.sectionEnd
        ].joined(separator: "\n")
    }

    /// Find the range of the managed section (including markers) within a string.
    /// Returns nil if the section markers are not found.
    private func findManagedSectionRange(in content: String) -> Range<String.Index>? {
        guard let startRange = content.range(of: Self.sectionStart),
              let endRange = content.range(of: Self.sectionEnd)
        else {
            return nil
        }

        // Include the full range from start of opening marker to end of closing marker
        return startRange.lowerBound ..< endRange.upperBound
    }
}
