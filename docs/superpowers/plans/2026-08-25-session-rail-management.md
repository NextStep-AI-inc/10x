# Session Rail Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the session rail use its available height, expose bounded project and rail overflow, and support reversible archive plus confirmed deletion of session history.

**Architecture:** `SessionLibrary` owns active and archived transcript files and exposes typed mutation reports. Pure presentation models decide the five-session disclosure and scroll targets; `AppModel` coordinates runtime shutdown, confirmation, mutations, and routing; SwiftUI views render the rail, archive screen, and confirmation overlay.

**Tech Stack:** Swift 6, SwiftUI on macOS 15+, Observation, OmpKit actors, Swift Testing, AppKit-backed snapshot tests, Xcode 26.

**Design:** `docs/superpowers/specs/2026-08-25-session-rail-management-design.md`

---

## File map

- Modify `OmpKit/Sources/OmpKit/Sessions/SessionLibrary.swift`: list and mutate active/archive transcript collections.
- Modify `OmpKit/Tests/OmpKitTests/SessionLibraryTests.swift`: prove archive, restore, conflict, deletion, and project-directory safety.
- Modify `App/Shell/RailPresentation.swift`: emit only five recent sessions plus a connected disclosure item.
- Modify `Tests/TenXAppTests/RailPresentationTests.swift`: prove disclosure and per-project expansion behavior.
- Create `App/Shell/RailScrollNavigation.swift`: pure scroll-boundary and four-row target calculations.
- Create `Tests/TenXAppTests/RailScrollNavigationTests.swift`: prove boundary visibility and target clamping.
- Modify `App/Shell/RailAccessibility.swift`: centralize disclosure and chevron accessibility copy.
- Create `App/Sessions/SessionDeletionRequest.swift`: deletion scope, confirmation copy, and affected paths.
- Modify `App/Application/AppModel.swift`: coordinate archive/restore/delete operations and active-session cleanup.
- Modify `Tests/TenXAppTests/AppModelNavigationTests.swift`: prove archive routing, confirmation state, and active-route cleanup.
- Modify `App/Shell/FloatingRailView.swift`: full-height map, connected disclosures, chevrons, Archived navigation, and live context menus.
- Modify `App/Application/AppRoute.swift`: add the archived route.
- Modify `App/Shell/AppShellView.swift`: render archive content, confirmation overlay, and mutation errors.
- Create `App/Sessions/ArchivedSessionsView.swift`: grouped archive browser with restore/delete context actions.
- Create `App/Sessions/SessionDeletionConfirmationView.swift`: visible, snapshot-testable destructive confirmation.
- Modify `Tests/TenXAppTests/AccessibilityLabelTests.swift`: verify disclosure and destructive-action copy.
- Modify `Tests/TenXAppTests/ViewSnapshotTests.swift`: rail, archive, and confirmation states.
- Add/update PNGs in `Tests/TenXAppTests/ReferenceImages/`: approved visual baselines.

---

### Task 1: Add reversible transcript storage operations

**Files:**
- Modify: `OmpKit/Sources/OmpKit/Sessions/SessionLibrary.swift`
- Test: `OmpKit/Tests/OmpKitTests/SessionLibraryTests.swift`

- [ ] **Step 1: Write failing archive and restore tests**

Append tests that create distinct active and archive roots, archive one session, list it from the archive, restore it, and verify the original bucket-relative path is recovered:

```swift
@Test func archivesAndRestoresAResultWithoutChangingItsRelativePath() async throws {
    let container = makeTempRoot("archive-restore")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let activeFile = activeRoot.appendingPathComponent("-tmp-project/session.jsonl")
    try writeSession(
        at: activeFile,
        id: "archive-me",
        cwd: "/tmp/project",
        lastMessage: completeLast)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let archiveReport = await library.archive(paths: [activeFile.path])
    #expect(archiveReport.failures.isEmpty)
    #expect(await library.listAll().isEmpty)
    let archived = await library.listArchived()
    #expect(archived.map(\.sessionId) == ["archive-me"])
    #expect(archived.first?.path == archiveRoot
        .appendingPathComponent("-tmp-project/session.jsonl").path)

    let restoreReport = await library.restore(paths: archived.map(\.path))
    #expect(restoreReport.failures.isEmpty)
    #expect(await library.listArchived().isEmpty)
    #expect(await library.listAll().map(\.path) == [activeFile.path])
}

@Test func restoreNeverOverwritesAnActiveTranscript() async throws {
    let container = makeTempRoot("restore-conflict")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let relativePath = "-tmp-project/session.jsonl"
    let activeFile = activeRoot.appendingPathComponent(relativePath)
    let archivedFile = archiveRoot.appendingPathComponent(relativePath)
    try writeSession(at: activeFile, id: "active", cwd: "/tmp/project", lastMessage: completeLast)
    try writeSession(at: archivedFile, id: "archived", cwd: "/tmp/project", lastMessage: completeLast)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let report = await library.restore(paths: [archivedFile.path])

    #expect(report.succeededPaths.isEmpty)
    #expect(report.failures == [SessionMutationFailure(
        path: archivedFile.path,
        reason: .destinationExists)])
    #expect(FileManager.default.fileExists(atPath: activeFile.path))
    #expect(FileManager.default.fileExists(atPath: archivedFile.path))
}
```

- [ ] **Step 2: Run the storage tests and verify RED**

Run:

```bash
swift test --package-path OmpKit --filter SessionLibrary
```

Expected: compilation fails because `archiveRoot`, `archive(paths:)`, `restore(paths:)`, `listArchived()`, and mutation-report types do not exist.

- [ ] **Step 3: Add typed mutation results and active/archive scanning**

Add these public types above `SessionLibrary`:

```swift
public enum SessionMutationFailureReason: Sendable, Equatable {
    case invalidPath
    case missingSource
    case destinationExists
    case fileOperationFailed
}

public struct SessionMutationFailure: Sendable, Equatable {
    public let path: String
    public let reason: SessionMutationFailureReason

    public init(path: String, reason: SessionMutationFailureReason) {
        self.path = path
        self.reason = reason
    }
}

public struct SessionMutationReport: Sendable, Equatable {
    public let succeededPaths: [String]
    public let failures: [SessionMutationFailure]

    public init(succeededPaths: [String], failures: [SessionMutationFailure]) {
        self.succeededPaths = succeededPaths
        self.failures = failures
    }
}
```

Store both roots and make archived listing reuse the existing scanner:

```swift
private let root: URL
private let archiveRoot: URL

public init(
    root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".omp/agent/sessions"),
    archiveRoot: URL? = nil
) {
    self.root = root.standardizedFileURL
    self.archiveRoot = (archiveRoot ?? root.deletingLastPathComponent()
        .appendingPathComponent("archived-sessions")).standardizedFileURL
    (changeStream, changeContinuation) = AsyncStream<Void>.makeStream(
        bufferingPolicy: .bufferingNewest(1))
}

public func listAll() -> [SessionMetadata] {
    list(in: root)
}

public func listArchived() -> [SessionMetadata] {
    list(in: archiveRoot)
}

private func list(in collectionRoot: URL) -> [SessionMetadata] {
    let fileManager = FileManager.default
    guard let buckets = try? fileManager.contentsOfDirectory(
        at: collectionRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [])
    else { return [] }

    var results: [SessionMetadata] = []
    for bucket in buckets {
        guard (try? bucket.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { continue }
        guard let files = try? fileManager.contentsOfDirectory(
            at: bucket,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [])
        else { continue }
        for file in files where file.pathExtension == "jsonl" {
            if let metadata = scan(file) { results.append(metadata) }
        }
    }
    results.sort { $0.modified > $1.modified }
    return results
}
```

Implement movement without overwriting and preserve exactly two path levels (`bucket/file.jsonl`) below the collection root:

```swift
public func archive(paths: [String]) -> SessionMutationReport {
    move(paths: paths, from: root, to: archiveRoot)
}

public func restore(paths: [String]) -> SessionMutationReport {
    move(paths: paths, from: archiveRoot, to: root)
}

private func move(paths: [String], from sourceRoot: URL, to destinationRoot: URL)
    -> SessionMutationReport {
    var succeeded: [String] = []
    var failures: [SessionMutationFailure] = []
    let fileManager = FileManager.default

    for path in paths {
        guard let relativePath = relativeSessionPath(path, under: sourceRoot) else {
            failures.append(SessionMutationFailure(path: path, reason: .invalidPath))
            continue
        }
        let source = URL(filePath: path).standardizedFileURL
        let destination = destinationRoot.appending(path: relativePath)
        guard fileManager.fileExists(atPath: source.path) else {
            failures.append(SessionMutationFailure(path: path, reason: .missingSource))
            continue
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            failures.append(SessionMutationFailure(path: path, reason: .destinationExists))
            continue
        }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: destination)
            succeeded.append(path)
            invalidateCache(paths: [source.path, destination.path])
        } catch {
            failures.append(SessionMutationFailure(path: path, reason: .fileOperationFailed))
        }
    }
    refreshWatchers()
    emitChange()
    return SessionMutationReport(succeededPaths: succeeded, failures: failures)
}

private func relativeSessionPath(_ path: String, under collectionRoot: URL) -> String? {
    let rootComponents = collectionRoot.standardizedFileURL.pathComponents
    let file = URL(filePath: path).standardizedFileURL
    let fileComponents = file.pathComponents
    guard file.pathExtension == "jsonl",
          fileComponents.starts(with: rootComponents),
          fileComponents.count == rootComponents.count + 2
    else { return nil }
    return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
}

private func invalidateCache(paths: [String]) {
    let changedPaths = Set(paths)
    cache = cache.filter { !changedPaths.contains($0.key.path) }
}
```

Replace watcher discovery with both collection roots:

```swift
private func refreshWatchers() {
    let desired = [root, archiveRoot].flatMap(watchedURLs)
    let desiredPaths = Set(desired.map(\.path))
    for path in watchers.keys where !desiredPaths.contains(path) {
        watchers.removeValue(forKey: path)?.cancel()
    }
    for url in desired where watchers[url.path] == nil { watch(url) }
}

private func watchedURLs(in collectionRoot: URL) -> [URL] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: collectionRoot.path) else { return [] }
    var desired = [collectionRoot]
    guard let buckets = try? fileManager.contentsOfDirectory(
        at: collectionRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [])
    else { return desired }
    for bucket in buckets where
        (try? bucket.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
        desired.append(bucket)
        if let files = try? fileManager.contentsOfDirectory(
            at: bucket,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []) {
            desired += files.filter { $0.pathExtension == "jsonl" }
        }
    }
    return desired
}
```

- [ ] **Step 4: Run the storage tests and verify GREEN**

Run:

```bash
swift test --package-path OmpKit --filter SessionLibrary
```

Expected: the archive, restore, conflict, listing, cache, and watcher tests pass.

- [ ] **Step 5: Write the failing deletion safety test**

```swift
@Test func deleteRemovesOnlySuppliedTranscriptsAndNeverTheProjectDirectory() async throws {
    let container = makeTempRoot("delete-safety")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let projectRoot = container.appendingPathComponent("source-project")
    let keptSource = projectRoot.appendingPathComponent("Keep.swift")
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    try Data("struct Keep {}".utf8).write(to: keptSource)
    let first = activeRoot.appendingPathComponent("-source-project/first.jsonl")
    let second = activeRoot.appendingPathComponent("-source-project/second.jsonl")
    try writeSession(at: first, id: "first", cwd: projectRoot.path, lastMessage: completeLast)
    try writeSession(at: second, id: "second", cwd: projectRoot.path, lastMessage: completeLast)
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)

    let report = await library.delete(paths: [first.path])

    #expect(report.failures.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: first.path))
    #expect(FileManager.default.fileExists(atPath: second.path))
    #expect(FileManager.default.fileExists(atPath: keptSource.path))
}
```

- [ ] **Step 6: Run the deletion test and verify RED**

Run the same `swift test` command. Expected: compilation fails because `delete(paths:)` does not exist.

- [ ] **Step 7: Implement path-bounded deletion**

```swift
public func delete(paths: [String]) -> SessionMutationReport {
    var succeeded: [String] = []
    var failures: [SessionMutationFailure] = []
    let fileManager = FileManager.default

    for path in paths {
        let isActive = relativeSessionPath(path, under: root) != nil
        let isArchived = relativeSessionPath(path, under: archiveRoot) != nil
        guard isActive || isArchived else {
            failures.append(SessionMutationFailure(path: path, reason: .invalidPath))
            continue
        }
        guard fileManager.fileExists(atPath: path) else {
            failures.append(SessionMutationFailure(path: path, reason: .missingSource))
            continue
        }
        do {
            try fileManager.removeItem(atPath: path)
            succeeded.append(path)
            invalidateCache(paths: [path])
        } catch {
            failures.append(SessionMutationFailure(path: path, reason: .fileOperationFailed))
        }
    }
    refreshWatchers()
    emitChange()
    return SessionMutationReport(succeededPaths: succeeded, failures: failures)
}
```

- [ ] **Step 8: Run all OmpKit tests and commit**

Run:

```bash
swift test --package-path OmpKit
```

Expected: all OmpKit tests pass with no new warnings.

Commit:

```bash
git add OmpKit/Sources/OmpKit/Sessions/SessionLibrary.swift OmpKit/Tests/OmpKitTests/SessionLibraryTests.swift
git commit -m "feat(sessions): add archive and deletion storage"
```

---

### Task 2: Bound each project to five recent sessions

**Files:**
- Modify: `App/Shell/RailPresentation.swift`
- Test: `Tests/TenXAppTests/RailPresentationTests.swift`

- [ ] **Step 1: Replace the all-sessions assertion with failing disclosure tests**

Create seven sessions and assert the default and expanded presentations:

```swift
@Test func railPresentationShowsFiveRecentSessionsAndConnectedOverflow() {
    let sessions = (1...7).map { index in
        metadata(path: "/sessions/\(index).jsonl", title: "Session \(index)", modified: 8 - index)
    }
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: sessions)

    let items = RailPresentation.items(
        groups: [group],
        selectedSessionPath: nil,
        expandedProjectIDs: [])

    #expect(items.filter { $0.kind == .session }.count == 5)
    #expect(items.last?.kind == .disclosure)
    #expect(items.last?.markerLabel == "...")
    #expect(items.last?.treePosition == .terminalChild)
    #expect(items.last?.disclosure == RailProjectDisclosure(
        projectID: group.id,
        hiddenCount: 2,
        isExpanded: false))
}

@Test func railPresentationExpandsAndCollapsesOneProjectWithoutReordering() {
    let sessions = (1...7).map { index in
        metadata(path: "/sessions/\(index).jsonl", title: "Session \(index)", modified: 8 - index)
    }
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: sessions)

    let items = RailPresentation.items(
        groups: [group],
        selectedSessionPath: sessions[6].path,
        expandedProjectIDs: [group.id])

    #expect(items.filter { $0.kind == .session }.map(\.id) == sessions.map { "session:\($0.path)" })
    #expect(items.last?.disclosure?.isExpanded == true)
    #expect(items.last?.disclosure?.hiddenCount == 2)
    #expect(items.first { $0.id == "session:\(sessions[6].path)" }?.isSelected == true)
}
```

Update the test helper to accept deterministic modification dates:

```swift
private func metadata(path: String, title: String, modified: Int = 0) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/project",
        title: title,
        created: Date(timeIntervalSince1970: TimeInterval(modified)),
        modified: Date(timeIntervalSince1970: TimeInterval(modified)),
        sizeBytes: 10,
        status: .complete)
}
```

- [ ] **Step 2: Run the presentation tests and verify RED**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/RailPresentationTests test
```

Expected: compilation fails because disclosure types and `expandedProjectIDs` do not exist.

- [ ] **Step 3: Add the connected disclosure model and five-item limit**

Add a disclosure value and extend item content/kind:

```swift
struct RailProjectDisclosure: Equatable {
    let projectID: String
    let hiddenCount: Int
    let isExpanded: Bool
}

enum Kind: Equatable {
    case project
    case session
    case disclosure
}

enum Content: Equatable {
    case project(ProjectSessionGroup)
    case session(SessionMetadata)
    case disclosure(RailProjectDisclosure)
}

var disclosure: RailProjectDisclosure? {
    guard case .disclosure(let disclosure) = content else { return nil }
    return disclosure
}

var kind: Kind {
    switch content {
    case .project: .project
    case .session: .session
    case .disclosure: .disclosure
    }
}

var id: String {
    switch content {
    case .project(let group): "project:\(group.id)"
    case .session(let metadata): "session:\(metadata.path)"
    case .disclosure(let disclosure): "disclosure:\(disclosure.projectID)"
    }
}
```

Use a five-session limit and append a terminal disclosure only when the group has more:

```swift
static let recentSessionLimit = 5

static func items(
    groups: [ProjectSessionGroup],
    selectedSessionPath: String?,
    expandedProjectIDs: Set<String> = []
) -> [RailPresentationItem] {
    groups.flatMap { group in
        let isExpanded = expandedProjectIDs.contains(group.id)
        let visibleSessions = isExpanded
            ? group.sessions
            : Array(group.sessions.prefix(recentSessionLimit))
        let hiddenCount = max(0, group.sessions.count - recentSessionLimit)
        let hasDisclosure = hiddenCount > 0
        let projectItem = RailPresentationItem(
            content: .project(group),
            isSelected: false,
            markerLabel: markerLabel(for: group.displayName),
            treePosition: .root)
        let sessionItems = visibleSessions.enumerated().map { index, metadata in
            RailPresentationItem(
                content: .session(metadata),
                isSelected: metadata.path == selectedSessionPath,
                markerLabel: String(format: "%02d", index + 1),
                treePosition: hasDisclosure || index < visibleSessions.count - 1
                    ? .child
                    : .terminalChild)
        }
        guard hasDisclosure else { return [projectItem] + sessionItems }
        let disclosureItem = RailPresentationItem(
            content: .disclosure(RailProjectDisclosure(
                projectID: group.id,
                hiddenCount: hiddenCount,
                isExpanded: isExpanded)),
            isSelected: false,
            markerLabel: "...",
            treePosition: .terminalChild)
        return [projectItem] + sessionItems + [disclosureItem]
    }
}
```

- [ ] **Step 4: Run the presentation tests and commit**

Run the focused command from Step 2. Expected: all rail-presentation tests pass.

Commit:

```bash
git add App/Shell/RailPresentation.swift Tests/TenXAppTests/RailPresentationTests.swift
git commit -m "feat(shell): bound project session groups"
```

---

### Task 3: Add session-management state and orchestration

**Files:**
- Create: `App/Sessions/SessionDeletionRequest.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Application/AppRoute.swift`
- Test: `Tests/TenXAppTests/AppModelNavigationTests.swift`

- [ ] **Step 1: Write failing route and confirmation tests**

```swift
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func openArchivedSessionsSelectsArchivedRoute() {
    let model = AppModel()
    model.openArchivedSessions()
    #expect(model.route == .archivedSessions)
}

@MainActor
@Test func projectDeletionCopyNamesCountAndProtectsProjectFiles() {
    let model = AppModel()
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/Project", directoryHint: .isDirectory),
        sessions: [navigationMetadata("/sessions/one.jsonl"), navigationMetadata("/sessions/two.jsonl")])

    model.requestDeleteProject(group)

    #expect(model.pendingDeletion?.title == "Delete sessions for Project?")
    #expect(model.pendingDeletion?.message
        == "This permanently deletes 2 session transcripts. Project files are not changed.")
    #expect(model.pendingDeletion?.paths == group.sessions.map(\.path))
}

@MainActor
@Test func archivingTheOpenRouteReturnsToNewSession() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-archive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let file = activeRoot.appendingPathComponent("-tmp-project/open.jsonl")
    try writeNavigationSession(at: file, id: "open", cwd: "/tmp/project")
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: library))
    await model.reloadSessions()
    let session = try #require(model.sessions.first)
    model.route = .session(session.path)

    await model.archiveSession(session)

    #expect(model.route == .newSession)
    #expect(model.sessions.isEmpty)
    #expect(model.archivedSessions.map(\.sessionId) == ["open"])
}

private func navigationMetadata(_ path: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/Project",
        title: "Session",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 10,
        status: .complete)
}

private func writeNavigationSession(at url: URL, id: String, cwd: String) throws {
    let content = """
    {"type":"session","version":3,"id":"\(id)","timestamp":"2026-01-01T00:00:00.000Z","cwd":"\(cwd)"}
    {"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","content":"done"}}
    """
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try Data(content.utf8).write(to: url)
}

private struct MissingOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpInstallation? { nil }
}
```

- [ ] **Step 2: Run navigation tests and verify RED**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/AppModelNavigationTests test
```

Expected: compilation fails because the archive route and deletion request state do not exist.

- [ ] **Step 3: Define deletion scope and exact confirmation copy**

Create `SessionDeletionRequest.swift`:

```swift
import OmpKit

enum SessionDeletionRequest: Identifiable, Equatable {
    case session(SessionMetadata)
    case project(ProjectSessionGroup)

    var id: String {
        switch self {
        case .session(let metadata): "session:\(metadata.path)"
        case .project(let group): "project:\(group.id)"
        }
    }

    var paths: [String] {
        switch self {
        case .session(let metadata): [metadata.path]
        case .project(let group): group.sessions.map(\.path)
        }
    }

    var title: String {
        switch self {
        case .session(let metadata):
            "Delete \(metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session")?"
        case .project(let group):
            "Delete sessions for \(group.displayName)?"
        }
    }

    var message: String {
        switch self {
        case .session:
            "This permanently deletes the session transcript. Project files are not changed."
        case .project(let group):
            let count = group.sessions.count
            let noun = count == 1 ? "transcript" : "transcripts"
            return "This permanently deletes \(count) session \(noun). Project files are not changed."
        }
    }

    var errorSubject: String {
        switch self {
        case .session(let metadata):
            metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
        case .project(let group):
            "\(group.displayName) sessions"
        }
    }
}
```

Replace `AppRoute` with the exhaustive route list:

```swift
enum AppRoute: Equatable {
    case setup
    case newSession
    case session(String)
    case archivedSessions
    case settings
}
```

- [ ] **Step 4: Add AppModel archive state and action entry points**

Add observable state:

```swift
var archivedSessions: [SessionMetadata] = []
var pendingDeletion: SessionDeletionRequest?
var sessionActionError: String?
```

Add routing, reload, requests, and mutations:

```swift
func openArchivedSessions() {
    route = .archivedSessions
    Task { await reloadArchivedSessions() }
}

func requestDeleteSession(_ metadata: SessionMetadata) {
    pendingDeletion = .session(metadata)
}

func requestDeleteProject(_ group: ProjectSessionGroup) {
    pendingDeletion = .project(group)
}

func cancelDeletion() {
    pendingDeletion = nil
}

func archiveSession(_ metadata: SessionMetadata) async {
    await mutateActive(
        paths: [metadata.path],
        action: "archive",
        subject: sessionDisplayName(metadata)) {
        await dependencies.sessionLibrary.archive(paths: [metadata.path])
    }
}

func archiveProject(_ group: ProjectSessionGroup) async {
    let paths = group.sessions.map(\.path)
    await mutateActive(
        paths: paths,
        action: "archive",
        subject: "\(group.displayName) sessions") {
        await dependencies.sessionLibrary.archive(paths: paths)
    }
}

func restoreSession(_ metadata: SessionMetadata) async {
    await finish(
        await dependencies.sessionLibrary.restore(paths: [metadata.path]),
        action: "restore",
        subject: sessionDisplayName(metadata))
}

func restoreProject(_ group: ProjectSessionGroup) async {
    await finish(
        await dependencies.sessionLibrary.restore(paths: group.sessions.map(\.path)),
        action: "restore",
        subject: "\(group.displayName) sessions")
}

func confirmDeletion() async {
    guard let request = pendingDeletion else { return }
    pendingDeletion = nil
    await closeActiveSessionIfNeeded(paths: request.paths)
    await finish(
        await dependencies.sessionLibrary.delete(paths: request.paths),
        action: "delete",
        subject: request.errorSubject)
}

func dismissSessionActionError() {
    sessionActionError = nil
}

private func mutateActive(
    paths: [String],
    action: String,
    subject: String,
    operation: () async -> SessionMutationReport
) async {
    await closeActiveSessionIfNeeded(paths: paths)
    await finish(await operation(), action: action, subject: subject)
}

private func closeActiveSessionIfNeeded(paths: [String]) async {
    guard case .session(let path) = route, paths.contains(path) else { return }
    await processManager?.close(sessionPath: path)
    activeSession = nil
    route = .newSession
}

private func finish(
    _ report: SessionMutationReport,
    action: String,
    subject: String
) async {
    if !report.failures.isEmpty {
        let count = report.failures.count
        sessionActionError = "Could not \(action) \(subject). \(count) session "
            + (count == 1 ? "file remains unchanged." : "files remain unchanged.")
    }
    await reloadSessions()
    await reloadArchivedSessions()
}

func reloadArchivedSessions() async {
    archivedSessions = await dependencies.sessionLibrary.listArchived()
}

private func sessionDisplayName(_ metadata: SessionMetadata) -> String {
    metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
}
```

Call `reloadArchivedSessions()` from `bootstrap()` after active sessions load.

- [ ] **Step 5: Run navigation tests and verify GREEN**

Run the focused command from Step 2. Expected: archive routing, confirmation copy, and active-route cleanup tests pass.

- [ ] **Step 6: Commit application state**

```bash
git add App/Application/AppModel.swift App/Application/AppRoute.swift \
  App/Sessions/SessionDeletionRequest.swift Tests/TenXAppTests/AppModelNavigationTests.swift
git commit -m "feat(sessions): coordinate archive and deletion actions"
```

---

### Task 4: Add testable rail scrolling and full-height presentation

**Files:**
- Create: `App/Shell/RailScrollNavigation.swift`
- Create: `Tests/TenXAppTests/RailScrollNavigationTests.swift`
- Modify: `App/Shell/FloatingRailView.swift`
- Modify: `App/Shell/RailAccessibility.swift`
- Modify: `Tests/TenXAppTests/AccessibilityLabelTests.swift`

- [ ] **Step 1: Write failing scroll-boundary tests**

```swift
import Testing
@testable import TenXApp

@Test func railScrollNavigationShowsOnlyAvailableDirections() {
    let top = RailScrollNavigation(offset: 0, contentHeight: 640, viewportHeight: 320)
    #expect(!top.canScrollUp)
    #expect(top.canScrollDown)

    let middle = RailScrollNavigation(offset: 160, contentHeight: 640, viewportHeight: 320)
    #expect(middle.canScrollUp)
    #expect(middle.canScrollDown)

    let bottom = RailScrollNavigation(offset: 320, contentHeight: 640, viewportHeight: 320)
    #expect(bottom.canScrollUp)
    #expect(!bottom.canScrollDown)
}

@Test func railScrollNavigationMovesFourRowsAndClampsToBounds() {
    let middle = RailScrollNavigation(offset: 160, contentHeight: 640, viewportHeight: 320)
    #expect(middle.target(for: .up) == 32)
    #expect(middle.target(for: .down) == 288)

    let nearBottom = RailScrollNavigation(offset: 300, contentHeight: 640, viewportHeight: 320)
    #expect(nearBottom.target(for: .down) == 320)
}
```

- [ ] **Step 2: Run the new test file and verify RED**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/RailScrollNavigationTests test
```

Expected: compilation fails because `RailScrollNavigation` and direction do not exist.

- [ ] **Step 3: Implement the pure scroll calculation**

Create `RailScrollNavigation.swift`:

```swift
import CoreGraphics

enum RailScrollDirection {
    case up
    case down
}

struct RailScrollNavigation: Equatable {
    static let rowHeight: CGFloat = 32
    static let rowsPerStep: CGFloat = 4

    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    static let zero = RailScrollNavigation(offset: 0, contentHeight: 0, viewportHeight: 0)

    private var maximumOffset: CGFloat {
        max(0, contentHeight - viewportHeight)
    }

    var canScrollUp: Bool { offset > 1 }
    var canScrollDown: Bool { offset < maximumOffset - 1 }

    func target(for direction: RailScrollDirection) -> CGFloat {
        let distance = Self.rowHeight * Self.rowsPerStep
        switch direction {
        case .up: max(0, offset - distance)
        case .down: min(maximumOffset, offset + distance)
        }
    }
}
```

- [ ] **Step 4: Run the scroll tests and verify GREEN**

Run the focused command from Step 2. Expected: both tests pass.

- [ ] **Step 5: Replace the rail's 58-percent cap with a flexible scroll region**

In `FloatingRailView`, add state:

```swift
@State private var expandedProjectIDs: Set<String> = []
@State private var scrollPosition = ScrollPosition()
@State private var scrollNavigation = RailScrollNavigation.zero
```

Pass `expandedProjectIDs` only while visually expanded:

```swift
private var items: [RailPresentationItem] {
    RailPresentation.items(
        groups: groups,
        selectedSessionPath: selectedSessionPath,
        expandedProjectIDs: expansion.isExpanded ? expandedProjectIDs : [])
}
```

Remove the `GeometryReader`, spacer pair, `sessionMapHeight`, and fixed map frame. Place `sessionMap` directly between the wordmark and bottom utilities with `.frame(maxHeight: .infinity)`.

Attach geometry and position tracking to the existing `ScrollView`:

```swift
.scrollPosition($scrollPosition)
.onScrollGeometryChange(for: RailScrollNavigation.self) { geometry in
    RailScrollNavigation(
        offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
        contentHeight: geometry.contentSize.height,
        viewportHeight: geometry.containerSize.height)
} action: { _, newValue in
    scrollNavigation = newValue
}
.overlay(alignment: .top) {
    if scrollNavigation.canScrollUp { scrollChevron(.up) }
}
.overlay(alignment: .bottom) {
    if scrollNavigation.canScrollDown { scrollChevron(.down) }
}
```

Add the lightweight control and honor reduced motion:

```swift
private func scrollChevron(_ direction: RailScrollDirection) -> some View {
    Button {
        let action = { scrollPosition.scrollTo(y: scrollNavigation.target(for: direction)) }
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        }
    } label: {
        Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(.white.opacity(0.9))
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(RailAccessibility.scrollLabel(direction))
}
```

- [ ] **Step 6: Render the connected project disclosure**

Add `.disclosure` handling to `itemButton`:

```swift
case .disclosure(let disclosure):
    if expansion.isExpanded {
        Button {
            if disclosure.isExpanded {
                expandedProjectIDs.remove(disclosure.projectID)
            } else {
                expandedProjectIDs.insert(disclosure.projectID)
            }
        } label: {
            HStack(spacing: 12) {
                RailTreeMarker(label: "...", position: .terminalChild, isSelected: false)
                    .frame(width: 34, height: 28)
                Text(disclosure.isExpanded
                    ? "Show recent 5"
                    : "Show \(disclosure.hiddenCount) more")
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 18)
        .frame(height: 32)
        .accessibilityLabel(RailAccessibility.disclosureLabel(
            hiddenCount: disclosure.hiddenCount,
            isExpanded: disclosure.isExpanded))
    } else {
        RailTreeMarker(label: "...", position: .terminalChild, isSelected: false)
            .frame(width: 34, height: 28)
            .padding(.leading, 18)
            .frame(height: 32)
            .accessibilityLabel(RailAccessibility.hiddenSessionsLabel(disclosure.hiddenCount))
    }
```

Extend the focus enum and apply it to expanded disclosure buttons:

```swift
private enum RailFocus: Hashable {
    case settings
    case project(String)
    case session(String)
    case disclosure(String)
}
```

On the expanded disclosure button add:

```swift
.focusEffectDisabled()
.focused($focusedItem, equals: .disclosure(disclosure.projectID))
```

- [ ] **Step 7: Add live context menus and pinned Archived navigation**

Attach menus to existing session and project buttons:

```swift
.contextMenu {
    Button("Archive Session", systemImage: "archivebox") {
        Task { await model.archiveSession(metadata) }
    }
    Button("Delete Session...", systemImage: "trash", role: .destructive) {
        model.requestDeleteSession(metadata)
    }
}
```

```swift
.contextMenu {
    Button("Archive Project Sessions", systemImage: "archivebox") {
        Task { await model.archiveProject(group) }
    }
    Button("Delete Project Sessions...", systemImage: "trash", role: .destructive) {
        model.requestDeleteProject(group)
    }
}
```

Add a 44-point bottom button below the flexible map and above provider usage:

```swift
Button(action: model.openArchivedSessions) {
    HStack(spacing: 12) {
        Image(systemName: "archivebox")
            .frame(width: 34)
        if expansion.isExpanded { Text("Archived") }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
.padding(.leading, 18)
.frame(height: 44)
.help("Archived sessions")
.accessibilityLabel("Archived sessions")
```

- [ ] **Step 8: Add accessibility-copy assertions, run focused tests, and commit**

Add exact helpers in `RailAccessibility.swift` and use them from the disclosure and chevron controls:

```swift
static func disclosureLabel(hiddenCount: Int, isExpanded: Bool) -> String {
    isExpanded ? "Show recent 5 sessions" : "Show \(hiddenCount) more sessions"
}

static func hiddenSessionsLabel(_ hiddenCount: Int) -> String {
    "\(hiddenCount) more sessions"
}

static func scrollLabel(_ direction: RailScrollDirection) -> String {
    direction == .up ? "Show earlier rail items" : "Show later rail items"
}
```

Add these assertions in `AccessibilityLabelTests.swift`:

```swift
@Test func railOverflowAccessibilityNamesActionsAndCounts() {
    #expect(RailAccessibility.disclosureLabel(hiddenCount: 2, isExpanded: false)
        == "Show 2 more sessions")
    #expect(RailAccessibility.disclosureLabel(hiddenCount: 2, isExpanded: true)
        == "Show recent 5 sessions")
    #expect(RailAccessibility.hiddenSessionsLabel(2) == "2 more sessions")
    #expect(RailAccessibility.scrollLabel(.up) == "Show earlier rail items")
    #expect(RailAccessibility.scrollLabel(.down) == "Show later rail items")
}
```

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/RailPresentationTests \
  -only-testing:TenXAppTests/RailScrollNavigationTests \
  -only-testing:TenXAppTests/AccessibilityLabelTests test
```

Expected: all focused rail tests pass.

Commit:

```bash
git add App/Shell/FloatingRailView.swift App/Shell/RailScrollNavigation.swift \
  App/Shell/RailAccessibility.swift \
  Tests/TenXAppTests/RailScrollNavigationTests.swift \
  Tests/TenXAppTests/AccessibilityLabelTests.swift
git commit -m "feat(shell): add bounded rail navigation"
```

---

### Task 5: Build the archive screen and destructive confirmation

**Files:**
- Create: `App/Sessions/ArchivedSessionsView.swift`
- Create: `App/Sessions/SessionDeletionConfirmationView.swift`
- Modify: `App/Shell/AppShellView.swift`
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`
- Add: `Tests/TenXAppTests/ReferenceImages/archived-sessions-empty.png`
- Add: `Tests/TenXAppTests/ReferenceImages/archived-sessions-populated.png`
- Add: `Tests/TenXAppTests/ReferenceImages/session-deletion-confirmation.png`

- [ ] **Step 1: Write failing archive and confirmation snapshots**

Add snapshot tests with deterministic metadata:

```swift
@MainActor
@Test func emptyArchivedSessionsSnapshot() throws {
    let model = AppModel()
    model.route = .archivedSessions
    try assertSnapshot(
        ArchivedSessionsView(model: model),
        name: "archived-sessions-empty",
        size: CGSize(width: 900, height: 700))
}

@MainActor
@Test func populatedArchivedSessionsSnapshot() throws {
    let model = AppModel()
    model.archivedSessions = [
        snapshotSession(path: "/archive/one.jsonl", cwd: "/tmp/10x", title: "Rail cleanup", modified: 20),
        snapshotSession(path: "/archive/two.jsonl", cwd: "/tmp/10x", title: "Header polish", modified: 10),
        snapshotSession(path: "/archive/three.jsonl", cwd: "/tmp/NextStep", title: "Course navigation", modified: 5),
    ]
    try assertSnapshot(
        ArchivedSessionsView(model: model),
        name: "archived-sessions-populated",
        size: CGSize(width: 900, height: 700))
}

@MainActor
@Test func sessionDeletionConfirmationSnapshot() throws {
    let request = SessionDeletionRequest.session(snapshotSession(
        path: "/sessions/one.jsonl",
        cwd: "/tmp/10x",
        title: "Rail cleanup",
        modified: 20))
    try assertSnapshot(
        SessionDeletionConfirmationView(request: request, onCancel: {}, onDelete: {}),
        name: "session-deletion-confirmation",
        size: CGSize(width: 900, height: 700))
}
```

- [ ] **Step 2: Run snapshots and verify RED**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: compilation fails because both new views do not exist.

- [ ] **Step 3: Implement the grouped archive screen**

Create `ArchivedSessionsView.swift` with one component, existing project grouping, an honest empty state, and context menus:

```swift
import SwiftUI

struct ArchivedSessionsView: View {
    let model: AppModel

    private var groups: [ProjectSessionGroup] {
        ProjectSessionGrouper.groups(model.archivedSessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Archived")
                    .font(TenXTypography.title(size: 32))
                Text("Restore session history or delete it permanently.")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            if groups.isEmpty {
                Spacer()
                Label("No archived sessions", systemImage: "archivebox")
                    .font(TenXTypography.body(size: 14))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groups) { group in archivedGroup(group) }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .task { await model.reloadArchivedSessions() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Archived sessions")
    }

    private func archivedGroup(_ group: ProjectSessionGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.displayName)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                Spacer()
                Text("\(group.sessions.count)")
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            .padding(.bottom, 8)
            .contextMenu {
                Button("Restore Project Sessions", systemImage: "arrow.uturn.backward") {
                    Task { await model.restoreProject(group) }
                }
                Button("Delete Project Sessions...", systemImage: "trash", role: .destructive) {
                    model.requestDeleteProject(group)
                }
            }

            ForEach(group.sessions) { metadata in
                HStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Text(metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session")
                        .font(TenXTypography.body(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Text(metadata.modified, style: .date)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Restore Session", systemImage: "arrow.uturn.backward") {
                        Task { await model.restoreSession(metadata) }
                    }
                    Button("Delete Session...", systemImage: "trash", role: .destructive) {
                        model.requestDeleteSession(metadata)
                    }
                }
                .accessibilityLabel(metadata.title ?? "Untitled session")
            }
        }
    }
}
```

- [ ] **Step 4: Implement the snapshot-testable confirmation overlay**

Create `SessionDeletionConfirmationView.swift`:

```swift
import SwiftUI

struct SessionDeletionConfirmationView: View {
    let request: SessionDeletionRequest
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.white.opacity(0.82)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
            CornerCard(color: TenXPalette.color(TenXPalette.signalRedHex)) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(request.title)
                        .font(TenXTypography.title(size: 24))
                    Text(request.message)
                        .font(TenXTypography.body(size: 13))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    HStack {
                        Spacer()
                        Button("Cancel", action: onCancel)
                            .buttonStyle(GhostActionStyle())
                        Button("Delete", action: onDelete)
                            .buttonStyle(GhostActionStyle(
                                color: TenXPalette.color(TenXPalette.signalRedHex)))
                    }
                }
                .frame(width: 420)
            }
            .background(.white)
        }
        .onExitCommand(perform: onCancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title)
    }
}
```

- [ ] **Step 5: Route and overlay both views in AppShellView**

Add the archived route branch:

```swift
case .archivedSessions:
    ArchivedSessionsView(model: model)
```

Add overlays after search:

```swift
.overlay {
    if let request = model.pendingDeletion {
        SessionDeletionConfirmationView(
            request: request,
            onCancel: model.cancelDeletion,
            onDelete: { Task { await model.confirmDeletion() } })
    }
}
.alert(
    "Session action failed",
    isPresented: Binding(
        get: { model.sessionActionError != nil },
        set: { if !$0 { model.dismissSessionActionError() } })) {
    Button("OK", action: model.dismissSessionActionError)
} message: {
    Text(model.sessionActionError ?? "The session could not be changed.")
}
```

- [ ] **Step 6: Record references, inspect them, and run snapshots**

Record:

```bash
RECORD_SNAPSHOTS=1 xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' -only-testing:TenXAppTests/ViewSnapshotTests test
```

Inspect all new PNGs and the changed rail PNGs at original resolution. Confirm the connector ends in `...`, `Show N more` aligns with session labels, Archived is pinned, both chevrons are light but visible, and the confirmation text is not clipped.

Then run without recording:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:TenXAppTests/ViewSnapshotTests test
```

Expected: all snapshot tests pass against the recorded files.

- [ ] **Step 7: Commit archive UI**

```bash
git add App/Sessions/ArchivedSessionsView.swift \
  App/Sessions/SessionDeletionConfirmationView.swift App/Shell/AppShellView.swift \
  Tests/TenXAppTests/ViewSnapshotTests.swift Tests/TenXAppTests/ReferenceImages
git commit -m "feat(sessions): add archived session management UI"
```

---

### Task 6: Verify the integrated Release experience

**Files:**
- Modify only files required to fix failures caused by Tasks 1-5; do not absorb unrelated findings.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' test
```

Expected: all existing and new tests pass. Record the exact test count.

- [ ] **Step 2: Build Release from the feature worktree**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/tenx-session-rail-management-derived build
```

Expected: `** BUILD SUCCEEDED **` and the app exists at `/tmp/tenx-session-rail-management-derived/Build/Products/Release/10x.app`.

- [ ] **Step 3: Launch one isolated feature instance and verify it is visible**

Use the `launching-local-builds` workflow. Do not stop or replace another worktree's process. Launch the Release app with `open -n`, identify the new PID, bring that PID frontmost, and verify through Accessibility that it has one non-minimized window.

- [ ] **Step 4: Drive the rail as a user**

Using Accessibility and the real pointer/menus:

1. Check a short window and a tall window in collapsed and expanded states.
2. Confirm every project initially shows at most five sessions.
3. Confirm collapsed overflow ends the tree with `...`.
4. Expand the rail, click `Show N more`, and confirm only that project expands.
5. Confirm `Show recent 5` restores the bounded state.
6. Scroll to middle, top, and bottom; confirm chevrons appear only in valid directions and each click advances roughly four rows.
7. Right-click a session and project; confirm archive/delete actions and exact labels.
8. Archive a disposable test transcript, open Archived, restore it, and confirm it returns.
9. Trigger both deletion confirmations using disposable test transcripts; cancel once and delete once.
10. Confirm the source project directory and a sentinel source file remain untouched.

- [ ] **Step 5: Capture visual evidence**

Capture the expanded rail with `Show N more`, a scrolled rail with a directional chevron, the populated archive screen, and a delete confirmation. If macOS reports the app window as non-shareable, record that limitation and use the deterministic snapshot PNGs plus Accessibility evidence rather than claiming a live screenshot.

- [ ] **Step 6: Run final diff checks and commit verification fixes**

```bash
git diff --check
git status --short
git log --oneline main..HEAD
```

Expected: no whitespace errors, no untracked build artifacts, and only scoped session-rail commits.

If verification exposes a scoped failure, return to the task that owns that file, add a failing regression test, make the minimum fix, rerun that task's focused command plus the full suite, and commit the exact files named by `git status` with `fix(shell): address session rail verification`. Do not modify unrelated files.

Do not merge. Hand off the local branch, commit SHAs, exact test/build evidence, screenshots or snapshot paths, skipped checks, and the remaining manual test entry point.
