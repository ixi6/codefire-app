# Swift Team Sync + Memory Leak Fixes

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix broken team sync in the Swift app and resolve resource leaks causing Mac slowdown.

**Architecture:** Phase 1 fixes the sync lifecycle — persist the sync-enabled preference, auto-start SyncEngine on launch, and add missing DB columns. Phase 2 fixes resource leaks — URLSession leak in RealtimeClient, zombie terminal processes, leaked browser tab subscriptions, and runaway ContextEngine timers/tasks.

**Tech Stack:** Swift, SwiftUI, GRDB, URLSession, Combine, NWPathMonitor

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `swift/Sources/CodeFire/Services/AppSettings.swift` | Modify | Add `cloudSyncEnabled` UserDefaults setting |
| `swift/Sources/CodeFire/Services/PremiumService.swift` | Modify | Auto-start SyncEngine after team restore; read AppSettings for sync pref |
| `swift/Sources/CodeFire/Views/Premium/TeamSettingsView.swift` | Modify | Wire toggle to AppSettings instead of in-memory PremiumStatus |
| `swift/Sources/CodeFire/Models/TaskItem.swift` | Modify | Add `remoteOwnerId`/`remoteOwnerName` fields |
| `swift/Sources/CodeFire/Models/Note.swift` | Modify | Add `remoteOwnerId`/`remoteOwnerName` fields |
| `swift/Sources/CodeFire/Services/DatabaseService.swift` | Modify | Add migration v24 for remote owner columns |
| `swift/Sources/CodeFire/Services/SyncEngine.swift` | Modify | Write remote owner fields when pulling; use AppSettings |
| `swift/Sources/CodeFire/Services/RealtimeClient.swift` | Modify | Invalidate old URLSession before reconnect |
| `swift/Sources/CodeFire/CodeFireApp.swift` | Modify | Add `unregister` + `cleanup` to TerminalTracker |
| `swift/Sources/CodeFire/Terminal/TerminalWrapper.swift` | Modify | Call unregister + kill shell on dismantle |
| `swift/Sources/CodeFire/Views/Browser/BrowserViewModel.swift` | Modify | Use `[UUID: AnyCancellable]` dict, cancel on tab close |
| `swift/Sources/CodeFire/Services/ContextEngine.swift` | Modify | Stop polling timer properly; use child tasks for embedding |

---

## Task 1: Persist `cloudSyncEnabled` in AppSettings

**Files:**
- Modify: `swift/Sources/CodeFire/Services/AppSettings.swift:57-66` (Teams section)
- Modify: `swift/Sources/CodeFire/Services/AppSettings.swift:140` (init)

- [ ] **Step 1: Add `cloudSyncEnabled` property to AppSettings**

In `AppSettings.swift`, add after the `premiumEnabled` property (line 60):

```swift
@Published var cloudSyncEnabled: Bool {
    didSet { UserDefaults.standard.set(cloudSyncEnabled, forKey: "cloudSyncEnabled") }
}
```

- [ ] **Step 2: Initialize from UserDefaults in init()**

In `AppSettings.swift` init(), after `self.premiumEnabled = ...` (line 140), add:

```swift
self.cloudSyncEnabled = defaults.object(forKey: "cloudSyncEnabled") as? Bool ?? false
```

- [ ] **Step 3: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/CodeFire/Services/AppSettings.swift
git commit -m "feat(sync): persist cloudSyncEnabled in UserDefaults"
```

---

## Task 2: Auto-start SyncEngine on app launch

**Files:**
- Modify: `swift/Sources/CodeFire/Services/PremiumService.swift:63-109` (restoreUserProfile)
- Modify: `swift/Sources/CodeFire/Views/Premium/TeamSettingsView.swift:430-439` (toggle binding)

- [ ] **Step 1: Import and access AppSettings in PremiumService.restoreUserProfile()**

At the end of `restoreUserProfile()`, after `await loadTeamMembership()` (line 104) and the print on line 105, add:

```swift
// Auto-start sync if user previously enabled it and has a team
if status.team != nil {
    let syncEnabled = SharedServices.shared.appSettings.cloudSyncEnabled
    status.syncEnabled = syncEnabled
    if syncEnabled {
        SyncEngine.shared.start()
    }
}
```

- [ ] **Step 2: Wire TeamSettingsView toggle to AppSettings**

In `TeamSettingsView.swift`, replace the toggle binding (lines 430-439) so it writes to AppSettings:

```swift
Toggle("Enable Cloud Sync", isOn: Binding(
    get: { premiumService.status.syncEnabled },
    set: { enabled in
        if enabled {
            SyncEngine.shared.start()
            premiumService.status.syncEnabled = true
            SharedServices.shared.appSettings.cloudSyncEnabled = true
        } else {
            SyncEngine.shared.stop()
            premiumService.status.syncEnabled = false
            SharedServices.shared.appSettings.cloudSyncEnabled = false
        }
    }
))
```

- [ ] **Step 3: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/CodeFire/Services/PremiumService.swift swift/Sources/CodeFire/Views/Premium/TeamSettingsView.swift
git commit -m "feat(sync): auto-start SyncEngine on launch when previously enabled"
```

---

## Task 3: Add `remoteOwnerId`/`remoteOwnerName` columns

**Files:**
- Modify: `swift/Sources/CodeFire/Services/DatabaseService.swift:590-596` (after v23 migration)
- Modify: `swift/Sources/CodeFire/Models/TaskItem.swift:23` (add fields)
- Modify: `swift/Sources/CodeFire/Models/Note.swift:13` (add fields)
- Modify: `swift/Sources/CodeFire/Services/SyncEngine.swift:493-513,524-535` (write fields on pull)

- [ ] **Step 1: Add migration v24 to DatabaseService**

In `DatabaseService.swift`, before `return migrator` (line 594), add:

```swift
migrator.registerMigration("v24_addRemoteOwnerColumns") { db in
    try db.alter(table: "taskItems") { t in
        t.add(column: "remoteOwnerId", .text)
        t.add(column: "remoteOwnerName", .text)
    }
    try db.alter(table: "notes") { t in
        t.add(column: "remoteOwnerId", .text)
        t.add(column: "remoteOwnerName", .text)
    }
}
```

- [ ] **Step 2: Add fields to TaskItem model**

In `TaskItem.swift`, after `var updatedAt: Date?` (line 23), add:

```swift
var remoteOwnerId: String?
var remoteOwnerName: String?
```

- [ ] **Step 3: Add fields to Note model**

In `Note.swift`, after `var isGlobal: Bool = false` (line 13), add:

```swift
var remoteOwnerId: String?
var remoteOwnerName: String?
```

- [ ] **Step 4: Write remote owner in SyncEngine.createLocalTask**

In `SyncEngine.swift`, in `createLocalTask(from:projectId:in:)`, after `task.labels = str` (line 509) and before `try task.insert(db)` (line 511), add:

```swift
task.remoteOwnerId = remote["created_by"] as? String
// Build display name from created_by if available
if let createdBy = remote["created_by"] as? String,
   createdBy != PremiumService.shared.status.user?.id {
    task.remoteOwnerName = remote["created_by_name"] as? String
}
```

**Note:** The `created_by_name` field may not exist in the remote response. This is a best-effort attribution — the important thing is `remoteOwnerId` is always set.

- [ ] **Step 5: Write remote owner in SyncEngine.createLocalNote**

In `SyncEngine.swift`, in `createLocalNote(from:projectId:in:)`, before `try note.insert(db)` (line 533), add:

```swift
note.remoteOwnerId = remote["created_by"] as? String
note.remoteOwnerName = remote["created_by_name"] as? String
```

- [ ] **Step 6: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add swift/Sources/CodeFire/Services/DatabaseService.swift swift/Sources/CodeFire/Models/TaskItem.swift swift/Sources/CodeFire/Models/Note.swift swift/Sources/CodeFire/Services/SyncEngine.swift
git commit -m "feat(sync): add remoteOwnerId/remoteOwnerName for team attribution"
```

---

## Task 4: Fix RealtimeClient URLSession leak on reconnect

**Files:**
- Modify: `swift/Sources/CodeFire/Services/RealtimeClient.swift:438-444` (handleDisconnect)

- [ ] **Step 1: Invalidate old session before reconnecting**

In `RealtimeClient.swift`, replace the reconnect timer closure (lines 439-445):

```swift
reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
    guard let self, self.state == .reconnecting else { return }
    print("RealtimeClient: reconnecting (attempt \(self.reconnectAttempts))")
    // Invalidate old session to prevent URLSession/thread pool leak
    self.webSocket?.cancel(with: .goingAway, reason: nil)
    self.webSocket = nil
    self.session?.invalidateAndCancel()
    self.session = nil
    self.connect(accessToken: self.accessToken)
}
```

The key change is adding `self.session?.invalidateAndCancel()` and `self.session = nil` before calling `connect()`. The `disconnect()` method already does this correctly — `handleDisconnect()` was missing it.

- [ ] **Step 2: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/CodeFire/Services/RealtimeClient.swift
git commit -m "fix(realtime): invalidate old URLSession before reconnect to prevent thread pool leak"
```

---

## Task 5: Fix TerminalTracker zombie processes

**Files:**
- Modify: `swift/Sources/CodeFire/CodeFireApp.swift:6-31` (TerminalTracker)
- Modify: `swift/Sources/CodeFire/Terminal/TerminalWrapper.swift:128` (NSViewRepresentable)

- [ ] **Step 1: Add unregister + cleanup to TerminalTracker**

In `CodeFireApp.swift`, replace the TerminalTracker class (lines 6-31):

```swift
final class TerminalTracker {
    static let shared = TerminalTracker()
    private var terminals: [ObjectIdentifier: WeakTerminalRef] = [:]

    private struct WeakTerminalRef {
        weak var view: LocalProcessTerminalView?
    }

    func register(_ view: LocalProcessTerminalView) {
        terminals[ObjectIdentifier(view)] = WeakTerminalRef(view: view)
    }

    func unregister(_ view: LocalProcessTerminalView) {
        let key = ObjectIdentifier(view)
        // Kill the shell process before removing
        if let process = view.process {
            let pid = process.shellPid
            if pid > 0 {
                kill(pid, SIGHUP)
                kill(pid, SIGKILL)
            }
        }
        terminals.removeValue(forKey: key)
    }

    func terminateAll() {
        for (_, ref) in terminals {
            if let process = ref.view?.process {
                let pid = process.shellPid
                if pid > 0 {
                    kill(pid, SIGHUP)
                    kill(pid, SIGKILL)
                }
            }
        }
        terminals.removeAll()
    }
}
```

- [ ] **Step 2: Add dismantleNSView to TerminalWrapper**

In `TerminalWrapper.swift`, add a `static func dismantleNSView` method after `updateNSView` (after line 301):

```swift
static func dismantleNSView(_ nsView: FocusableTerminalView, coordinator: Coordinator) {
    TerminalTracker.shared.unregister(nsView)
    if let monitor = coordinator.mouseMonitor {
        NSEvent.removeMonitor(monitor)
        coordinator.mouseMonitor = nil
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/CodeFire/CodeFireApp.swift swift/Sources/CodeFire/Terminal/TerminalWrapper.swift
git commit -m "fix(terminal): unregister + kill shell processes when terminal tabs close"
```

---

## Task 6: Fix BrowserViewModel cancellable leak

**Files:**
- Modify: `swift/Sources/CodeFire/Views/Browser/BrowserViewModel.swift:8,14-24,27-31,42-57`

- [ ] **Step 1: Replace Set<AnyCancellable> with keyed dictionary**

In `BrowserViewModel.swift`, replace the entire file:

```swift
import Foundation
import Combine

class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabId: UUID?

    private var tabCancellables: [UUID: AnyCancellable] = [:]

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabId }
    }

    func newTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activeTabId = tab.id

        // Forward tab property changes to trigger view updates
        tabCancellables[tab.id] = tab.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func closeTab(_ id: UUID) {
        tabCancellables[id]?.cancel()
        tabCancellables.removeValue(forKey: id)
        tabs.removeAll { $0.id == id }
        if activeTabId == id {
            activeTabId = tabs.last?.id
        }
    }

    /// Find a tab by its UUID string.
    func tab(byId idString: String) -> BrowserTab? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return tabs.first { $0.id == uuid }
    }

    /// Open a new tab and optionally navigate to a URL. Returns the new tab.
    @discardableResult
    func openTab(url: String? = nil) -> BrowserTab {
        let tab = BrowserTab()
        tabs.append(tab)
        activeTabId = tab.id

        // Forward tab property changes
        tabCancellables[tab.id] = tab.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        if let url = url, !url.isEmpty {
            tab.navigate(to: url)
        }
        return tab
    }

    /// Switch active tab by UUID string. Returns true if found.
    @discardableResult
    func switchTab(to idString: String) -> Bool {
        guard let uuid = UUID(uuidString: idString) else { return false }
        guard tabs.contains(where: { $0.id == uuid }) else { return false }
        activeTabId = uuid
        return true
    }

    /// Close tab by UUID string. Returns true if found and closed.
    @discardableResult
    func closeTabById(_ idString: String) -> Bool {
        guard let uuid = UUID(uuidString: idString) else { return false }
        guard tabs.contains(where: { $0.id == uuid }) else { return false }
        closeTab(uuid)
        return true
    }

    /// Serialize all tabs to a JSON-compatible array.
    func tabsInfo() -> [[String: Any]] {
        tabs.map { tab in
            [
                "id": tab.id.uuidString,
                "title": tab.title,
                "url": tab.currentURL,
                "isActive": tab.id == activeTabId,
                "isLoading": tab.isLoading
            ] as [String: Any]
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/CodeFire/Views/Browser/BrowserViewModel.swift
git commit -m "fix(browser): cancel Combine subscriptions when tabs close to prevent memory leak"
```

---

## Task 7: Fix ContextEngine polling timer + embedding task cancellation

**Files:**
- Modify: `swift/Sources/CodeFire/Services/ContextEngine.swift:87-94,99-106,559-644`
- Modify: `swift/Sources/CodeFire/CodeFireApp.swift:217-240` (onAppear)

- [ ] **Step 1: Stop polling timer in stopWatching()**

In `ContextEngine.swift`, update `stopWatching()` (lines 88-94) to also stop the poller:

```swift
func stopWatching() {
    fileWatcher?.stop()
    fileWatcher = nil
    embeddingTask?.cancel()
    embeddingTask = nil
    isEmbedding = false
    stopPollingForRequests()
}
```

- [ ] **Step 2: Replace Task.detached with child tasks in startBackgroundEmbedding**

In `ContextEngine.swift`, in `startBackgroundEmbedding()`, replace the `Task.detached` block (lines 608-632) with a structured concurrency version that respects cancellation:

```swift
let groupProcessed = await withTaskGroup(of: Int.self, returning: Int.self) { group in
    for batch in batchesCopy {
        group.addTask {
            guard !Task.isCancelled else { return 0 }
            let texts = batch.map { $0.content }
            let result = await client.embedBatch(texts)
            try? await DatabaseService.shared.dbQueue.write { db in
                for (i, item) in batch.enumerated() {
                    if i < result.embeddings.count && !result.embeddings[i].isEmpty {
                        let encoded = CodeChunk.encodeEmbedding(result.embeddings[i])
                        try db.execute(
                            sql: "UPDATE codeChunks SET embedding = ? WHERE id = ?",
                            arguments: [encoded, item.id]
                        )
                    }
                }
            }
            return batch.count
        }
    }
    var sum = 0
    for await count in group { sum += count }
    return sum
}
```

This replaces `Task.detached { await withTaskGroup ... }` with a direct `withTaskGroup` call. Child tasks created by `withTaskGroup` inherit the parent's cancellation — when `embeddingTask?.cancel()` fires, all in-flight batches will see `Task.isCancelled` and exit.

- [ ] **Step 3: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/CodeFire/Services/ContextEngine.swift
git commit -m "fix(context): stop polling timer on cleanup; use child tasks for cancellable embedding"
```

---

## Task 8: Cap LiveSessionMonitor.filesChanged

**Files:**
- Modify: `swift/Sources/CodeFire/Services/LiveSessionMonitor.swift:322-327`

- [ ] **Step 1: Add cap and use Set for O(1) lookups**

In `LiveSessionMonitor.swift`, replace the `filesChanged` accumulation block (lines 322-327). Find the section:

```swift
if !state.filesChanged.contains(filePath) {
    state.filesChanged.append(filePath)
}
```

Replace with:

```swift
if state.filesChanged.count < 500, !state.filesChanged.contains(filePath) {
    state.filesChanged.append(filePath)
}
```

This caps the array at 500 entries, preventing unbounded growth. The O(n) `contains` check is now bounded at n=500 which is negligible.

- [ ] **Step 2: Build to verify**

Run: `cd swift && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/CodeFire/Services/LiveSessionMonitor.swift
git commit -m "fix(monitor): cap filesChanged array at 500 to prevent unbounded growth"
```
