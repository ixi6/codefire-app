import Foundation
import GRDB
import CryptoKit

/// Main orchestrator for the context engine. Manages file watching,
/// chunking, embedding, and index lifecycle for the current project.
@MainActor
class ContextEngine: ObservableObject {
    @Published var indexStatus: String = "idle"
    @Published var totalChunks: Int = 0
    @Published var isIndexing: Bool = false
    @Published var lastError: String?
    @Published var indexProgress: Double = 0    // 0.0 to 1.0
    @Published var indexedFileCount: Int = 0
    @Published var totalFileCount: Int = 0
    @Published var lastIndexedAt: Date?

    private let embeddingClient = EmbeddingClient()
    private var fileWatcher: FileWatcher?
    private var currentProjectId: String?
    private var currentProjectPath: String?

    private let skipDirs: Set<String> = [
        "node_modules", ".build", "build", ".dart_tool", "__pycache__",
        ".next", "dist", ".git", ".gradle", "Pods", ".pub-cache",
        ".pub", "ios/Pods", "android/.gradle", ".swiftpm", "DerivedData",
        ".expo", "coverage", "vendor", "target"
    ]

    private let skipExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "ico", "webp",
        "woff", "woff2", "ttf", "eot",
        "zip", "tar", "gz", "dmg",
        "mp3", "mp4", "wav", "mov",
        "pdf", "lock", "sum"
    ]

    // MARK: - Public API

    /// Start indexing a project. Call when a project is selected.
    func startIndexing(projectId: String, projectPath: String) {
        guard !isIndexing else { return }

        // Stop watching previous project
        stopWatching()

        currentProjectId = projectId
        currentProjectPath = projectPath

        // Load existing index state
        if let state = try? DatabaseService.shared.dbQueue.read({ db in
            try IndexState.filter(Column("projectId") == projectId).fetchOne(db)
        }) {
            totalChunks = state.totalChunks
            lastIndexedAt = state.lastFullIndexAt
            if state.status == "ready" {
                indexStatus = "ready"
            }
        }

        // Start file watcher
        fileWatcher = FileWatcher(paths: [projectPath], debounceInterval: 2.0) { [weak self] changedPaths in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleFileChanges(changedPaths)
            }
        }
        fileWatcher?.start()

        // Run initial index
        Task {
            await performFullIndex()
        }
    }

    /// Stop watching and clean up.
    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// Force a full re-index of the current project.
    func rebuildIndex() {
        guard let projectId = currentProjectId, let _ = currentProjectPath else { return }
        Task {
            // Clear existing index
            try? await DatabaseService.shared.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM codeChunks WHERE projectId = ?", arguments: [projectId])
                try db.execute(sql: "DELETE FROM indexedFiles WHERE projectId = ?", arguments: [projectId])
            }
            await performFullIndex()
        }
    }

    /// Clear the index for the current project.
    func clearIndex() async {
        guard let projectId = currentProjectId else { return }
        do {
            try await DatabaseService.shared.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM codeChunks WHERE projectId = ?", arguments: [projectId])
                try db.execute(sql: "DELETE FROM indexedFiles WHERE projectId = ?", arguments: [projectId])
                try db.execute(sql: "DELETE FROM indexState WHERE projectId = ?", arguments: [projectId])
            }
            indexStatus = "idle"
            totalChunks = 0
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Full Index

    private func performFullIndex() async {
        guard let projectId = currentProjectId, let projectPath = currentProjectPath else { return }

        // Check API key
        guard ClaudeService.openRouterAPIKey != nil else {
            lastError = "OpenRouter API key not configured"
            return
        }

        isIndexing = true
        indexStatus = "indexing"
        indexProgress = 0
        indexedFileCount = 0
        totalFileCount = 0
        lastError = nil
        await updateIndexState(projectId: projectId, status: "indexing")

        do {
            // 1. Enumerate files
            let files = enumerateFiles(at: projectPath)
            totalFileCount = files.count

            // 2. Process each file
            var processedChunks = 0
            var pendingChunks: [(CodeChunk, String)] = []  // (chunk without embedding, text to embed)

            for (relativePath, fileURL) in files {
                let content: String
                do {
                    content = try String(contentsOf: fileURL, encoding: .utf8)
                } catch {
                    continue  // Skip unreadable files
                }

                // Check content hash
                let hash = sha256(content)
                let existingFile = try? await DatabaseService.shared.dbQueue.read { db in
                    try IndexedFile
                        .filter(Column("projectId") == projectId && Column("relativePath") == relativePath)
                        .fetchOne(db)
                }

                if let existing = existingFile, existing.contentHash == hash {
                    continue  // File unchanged, skip
                }

                // Delete old chunks for this file if it existed
                if let existing = existingFile {
                    try? await DatabaseService.shared.dbQueue.write { db in
                        try db.execute(sql: "DELETE FROM codeChunks WHERE fileId = ?", arguments: [existing.id])
                    }
                }

                // Chunk the file
                let language = CodeChunker.detectLanguage(from: relativePath)
                let chunks: [CodeChunker.Chunk]

                if language == "markdown" {
                    chunks = CodeChunker.chunkMarkdown(content: content, filePath: relativePath)
                } else if let lang = language {
                    chunks = CodeChunker.chunkFile(content: content, language: lang, filePath: relativePath)
                } else {
                    continue  // Skip unknown file types
                }

                // Create/update IndexedFile record
                let fileId = existingFile?.id ?? UUID().uuidString
                let indexedFile = IndexedFile(
                    id: fileId,
                    projectId: projectId,
                    relativePath: relativePath,
                    contentHash: hash,
                    language: language,
                    lastIndexedAt: Date()
                )
                try await DatabaseService.shared.dbQueue.write { db in
                    var record = indexedFile
                    try record.save(db)
                }

                // Queue chunks for embedding
                for chunk in chunks {
                    let codeChunk = CodeChunk(
                        id: UUID().uuidString,
                        fileId: fileId,
                        projectId: projectId,
                        chunkType: chunk.chunkType,
                        symbolName: chunk.symbolName,
                        content: chunk.content,
                        startLine: chunk.startLine,
                        endLine: chunk.endLine,
                        embedding: nil
                    )
                    pendingChunks.append((codeChunk, chunk.content))

                    // Batch embed when we hit 20
                    if pendingChunks.count >= 20 {
                        processedChunks += try await embedAndStore(pendingChunks)
                        pendingChunks.removeAll()
                        totalChunks = processedChunks
                    }
                }

                // Update file-level progress
                indexedFileCount += 1
                if totalFileCount > 0 {
                    indexProgress = Double(indexedFileCount) / Double(totalFileCount)
                }
            }

            // Embed remaining chunks
            if !pendingChunks.isEmpty {
                processedChunks += try await embedAndStore(pendingChunks)
            }

            // 3. Index git history
            processedChunks += await indexGitHistory(projectId: projectId, projectPath: projectPath)

            // 4. Clean up orphaned files
            try await cleanupOrphanedFiles(projectId: projectId, projectPath: projectPath)

            // 5. Update state
            totalChunks = processedChunks
            indexStatus = "ready"
            isIndexing = false
            indexProgress = 1.0
            lastIndexedAt = Date()
            await updateIndexState(projectId: projectId, status: "ready", totalChunks: processedChunks)

        } catch {
            lastError = error.localizedDescription
            indexStatus = "error"
            isIndexing = false
            await updateIndexState(projectId: projectId, status: "error", error: error.localizedDescription)
        }
    }

    // MARK: - Incremental Update

    private func handleFileChanges(_ changedPaths: [String]) async {
        guard let projectId = currentProjectId, let projectPath = currentProjectPath else { return }
        guard !isIndexing else { return }  // Don't interrupt full index

        for path in changedPaths {
            // Filter to project directory
            guard path.hasPrefix(projectPath) else { continue }
            let relativePath = String(path.dropFirst(projectPath.count + 1))

            // Skip non-indexable files
            guard shouldIndex(relativePath: relativePath) else { continue }

            let fileURL = URL(fileURLWithPath: path)
            let fm = FileManager.default

            if fm.fileExists(atPath: path) {
                // File created or modified
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let hash = sha256(content)

                // Check if unchanged
                let existing = try? await DatabaseService.shared.dbQueue.read { db in
                    try IndexedFile
                        .filter(Column("projectId") == projectId && Column("relativePath") == relativePath)
                        .fetchOne(db)
                }

                if let existing = existing, existing.contentHash == hash { continue }

                // Re-index this file
                if let existing = existing {
                    try? await DatabaseService.shared.dbQueue.write { db in
                        try db.execute(sql: "DELETE FROM codeChunks WHERE fileId = ?", arguments: [existing.id])
                    }
                }

                let language = CodeChunker.detectLanguage(from: relativePath)
                let chunks: [CodeChunker.Chunk]

                if language == "markdown" {
                    chunks = CodeChunker.chunkMarkdown(content: content, filePath: relativePath)
                } else if let lang = language {
                    chunks = CodeChunker.chunkFile(content: content, language: lang, filePath: relativePath)
                } else {
                    continue
                }

                let fileId = existing?.id ?? UUID().uuidString
                let indexedFile = IndexedFile(
                    id: fileId,
                    projectId: projectId,
                    relativePath: relativePath,
                    contentHash: hash,
                    language: language,
                    lastIndexedAt: Date()
                )

                try? await DatabaseService.shared.dbQueue.write { db in
                    var record = indexedFile
                    try record.save(db)
                }

                let pendingChunks: [(CodeChunk, String)] = chunks.map { chunk in
                    let codeChunk = CodeChunk(
                        id: UUID().uuidString,
                        fileId: fileId,
                        projectId: projectId,
                        chunkType: chunk.chunkType,
                        symbolName: chunk.symbolName,
                        content: chunk.content,
                        startLine: chunk.startLine,
                        endLine: chunk.endLine,
                        embedding: nil
                    )
                    return (codeChunk, chunk.content)
                }

                if !pendingChunks.isEmpty {
                    _ = try? await embedAndStore(pendingChunks)
                }

                // Update total count
                await updateTotalChunks(projectId: projectId)

            } else {
                // File deleted
                if let existing = try? await DatabaseService.shared.dbQueue.read({ db in
                    try IndexedFile
                        .filter(Column("projectId") == projectId && Column("relativePath") == relativePath)
                        .fetchOne(db)
                }) {
                    try? await DatabaseService.shared.dbQueue.write { db in
                        try db.execute(sql: "DELETE FROM codeChunks WHERE fileId = ?", arguments: [existing.id])
                        try existing.delete(db)
                    }
                    await updateTotalChunks(projectId: projectId)
                }
            }
        }
    }

    // MARK: - Git History Indexing

    private func indexGitHistory(projectId: String, projectPath: String) async -> Int {
        // Check if git repo
        let gitDir = (projectPath as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir) else { return 0 }

        // Run git log in a detached context to avoid MainActor issues with Process
        let gitLog: String? = await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["log", "--oneline", "--stat", "-200"]
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        }.value

        guard let gitLog, !gitLog.isEmpty else { return 0 }

        let chunks = CodeChunker.chunkGitHistory(gitLog)
        guard !chunks.isEmpty else { return 0 }

        // Use a special fileId for git history
        let gitFileId = "\(projectId)__git_history"
        let gitLogHash = sha256(gitLog)

        // Delete existing git chunks
        try? await DatabaseService.shared.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM codeChunks WHERE fileId = ?", arguments: [gitFileId])
            // Ensure IndexedFile record exists for git history
            var gitFile = IndexedFile(
                id: gitFileId,
                projectId: projectId,
                relativePath: ".git/history",
                contentHash: gitLogHash,
                language: nil,
                lastIndexedAt: Date()
            )
            try gitFile.save(db)
        }

        let pendingChunks: [(CodeChunk, String)] = chunks.map { chunk in
            let codeChunk = CodeChunk(
                id: UUID().uuidString,
                fileId: gitFileId,
                projectId: projectId,
                chunkType: chunk.chunkType,
                symbolName: chunk.symbolName,
                content: chunk.content,
                startLine: chunk.startLine,
                endLine: chunk.endLine,
                embedding: nil
            )
            return (codeChunk, chunk.content)
        }

        return (try? await embedAndStore(pendingChunks)) ?? 0
    }

    // MARK: - Helpers

    private func embedAndStore(_ chunks: [(CodeChunk, String)]) async throws -> Int {
        let texts = chunks.map { $0.1 }
        let result = await embeddingClient.embedBatch(texts)

        try await DatabaseService.shared.dbQueue.write { db in
            for (i, (var chunk, _)) in chunks.enumerated() {
                if i < result.embeddings.count && !result.embeddings[i].isEmpty {
                    chunk.embedding = CodeChunk.encodeEmbedding(result.embeddings[i])
                }
                try chunk.insert(db)
            }
        }

        return chunks.count
    }

    private func enumerateFiles(at path: String) -> [(String, URL)] {
        let fm = FileManager.default
        var results: [(String, URL)] = []

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: path + "/", with: "")

            // Skip directories
            if skipDirs.contains(where: { relativePath.hasPrefix($0 + "/") || relativePath == $0 }) {
                continue
            }

            // Skip non-indexable extensions
            let ext = fileURL.pathExtension.lowercased()
            if skipExtensions.contains(ext) { continue }

            // Only index known file types
            guard shouldIndex(relativePath: relativePath) else { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            results.append((relativePath, fileURL))
        }

        return results
    }

    private func shouldIndex(relativePath: String) -> Bool {
        // Check skip dirs
        if skipDirs.contains(where: { relativePath.hasPrefix($0 + "/") }) { return false }

        // Check extension
        let ext = (relativePath as NSString).pathExtension.lowercased()
        if skipExtensions.contains(ext) { return false }

        return CodeChunker.isIndexable(relativePath)
    }

    private nonisolated func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func cleanupOrphanedFiles(projectId: String, projectPath: String) async throws {
        let indexed = try await DatabaseService.shared.dbQueue.read { db in
            try IndexedFile.filter(Column("projectId") == projectId).fetchAll(db)
        }

        let fm = FileManager.default
        for file in indexed {
            if file.relativePath == ".git/history" { continue }  // Special case
            let fullPath = (projectPath as NSString).appendingPathComponent(file.relativePath)
            if !fm.fileExists(atPath: fullPath) {
                try await DatabaseService.shared.dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM codeChunks WHERE fileId = ?", arguments: [file.id])
                    try file.delete(db)
                }
            }
        }
    }

    private func updateIndexState(projectId: String, status: String, totalChunks: Int? = nil, error: String? = nil) async {
        try? await DatabaseService.shared.dbQueue.write { db in
            var state = try IndexState
                .filter(Column("projectId") == projectId)
                .fetchOne(db) ?? IndexState(
                    projectId: projectId,
                    status: status,
                    totalChunks: 0
                )
            state.status = status
            if let total = totalChunks { state.totalChunks = total }
            if let error = error { state.lastError = error }
            if status == "ready" { state.lastFullIndexAt = Date() }
            try state.save(db)
        }
    }

    private func updateTotalChunks(projectId: String) async {
        let count = try? await DatabaseService.shared.dbQueue.read { db in
            try CodeChunk.filter(Column("projectId") == projectId).fetchCount(db)
        }
        if let count = count {
            totalChunks = count
            await updateIndexState(projectId: projectId, status: "ready", totalChunks: count)
        }
    }
}
