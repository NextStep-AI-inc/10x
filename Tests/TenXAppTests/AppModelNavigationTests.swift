import Foundation
import OmpKit
import Testing
import Foundation
import OmpKit
@testable import TenXApp

@MainActor
@Test func openSettingsSelectsSettingsRoute() {
    let model = AppModel()

    model.openSettings()

    #expect(model.route == .settings)
}

@MainActor
@Test func leaveSettingsRestoresThePreviousRoute() {
    let model = AppModel()
    model.route = .archivedSessions

    model.openSettings()
    model.leaveSettings()

    #expect(model.route == .archivedSessions)
}

@MainActor
@Test func leaveSettingsFallsBackToNewSessionFromSetup() {
    let model = AppModel()
    model.route = .setup

    model.openSettings()
    model.leaveSettings()

    #expect(model.route == .newSession)
}

@MainActor
@Test func leaveSettingsRestoresSessionRoute() {
    let model = AppModel()
    model.route = .session("/tmp/session.jsonl")

    model.openSettings()
    model.leaveSettings()

    #expect(model.route == .session("/tmp/session.jsonl"))
}

@MainActor
@Test func leaveSettingsIsNoOpWhenNotOnSettings() {
    let model = AppModel()
    model.route = .archivedSessions

    model.leaveSettings()

    #expect(model.route == .archivedSessions)
}

@MainActor
@Test func settingsBackActionLeavesSettingsViaOnBack() {
    let model = AppModel()
    model.route = .newSession
    model.openSettings()

    // Mirrors AppShellView wiring: explicit closure, not a bare method reference.
    let onBack = { model.leaveSettings() }
    onBack()

    #expect(model.route == .newSession)
}

@MainActor
@Test func chooseIDESelectsSettingsAndRequestsPreferredIDEFocus() {
    let model = AppModel()

    model.openSettings(focus: .preferredIDE)

    #expect(model.route == .settings)
    #expect(model.settingsFocusTarget == .preferredIDE)
    model.consumeSettingsFocus()
    #expect(model.settingsFocusTarget == nil)
}

@MainActor
@Test func openNewSessionSelectsNewSessionRoute() {
    let model = AppModel()
    model.route = .settings

    model.openNewSession()

    #expect(model.route == .newSession)
}

@MainActor
@Test func openSearchPresentsSearchWithoutChangingRoute() {
    let model = AppModel()
    model.route = .session("/tmp/session.jsonl")

    model.openSearch()

    #expect(model.isSearchPresented)
    #expect(model.route == .session("/tmp/session.jsonl"))
}

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
        sessions: [
            navigationMetadata("/sessions/one.jsonl"),
            navigationMetadata("/sessions/two.jsonl"),
        ])

    model.requestDeleteProject(group)

    #expect(model.pendingDeletion?.title == "Delete sessions for Project?")
    #expect(model.pendingDeletion?.message
        == "This permanently deletes 2 session transcripts. Project files are not changed.")
    #expect(model.pendingDeletion?.paths == group.sessions.map(\.path))
}

@MainActor
@Test func projectDeletionCopyUsesSingularTranscript() {
    let model = AppModel()
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/Project", directoryHint: .isDirectory),
        sessions: [navigationMetadata("/sessions/one.jsonl")])

    model.requestDeleteProject(group)

    #expect(model.pendingDeletion?.message
        == "This permanently deletes 1 session transcript. Project files are not changed.")
}

@MainActor
@Test func sessionDeletionRequestHasExactIdentityAndCopy() {
    let model = AppModel()
    let session = navigationMetadata("/sessions/one.jsonl")

    model.requestDeleteSession(session)

    #expect(model.pendingDeletion?.id == "session:/sessions/one.jsonl")
    #expect(model.pendingDeletion?.paths == [session.path])
    #expect(model.pendingDeletion?.title == "Delete Session?")
    #expect(model.pendingDeletion?.message
        == "This permanently deletes the session transcript. Project files are not changed.")
    #expect(model.pendingDeletion?.errorSubject == "Session")
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
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: library))
    await model.reloadSessions()
    let session = try #require(model.sessions.first)
    model.route = .session(session.path)

    await model.archiveSession(session)

    #expect(model.route == .newSession)
    #expect(model.activeSession == nil)
    #expect(model.sessions.isEmpty)
    #expect(model.archivedSessions.map(\.sessionId) == ["open"])
}

@MainActor
@Test func failedArchiveNamesUnchangedSessionFile() async {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-failed-archive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    let library = SessionLibrary(root: container.appendingPathComponent("sessions"))
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: library))
    let missing = navigationMetadata(
        container.appendingPathComponent("sessions/bucket/missing.jsonl").path)

    await model.archiveSession(missing)

    #expect(model.sessionActionError
        == "Could not archive Session. 1 session file remains unchanged.")
}

@MainActor
@Test func successfulMutationClearsAnEarlierActionError() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-cleared-error-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: library))
    let missing = navigationMetadata(
        activeRoot.appendingPathComponent("bucket/missing.jsonl").path)
    await model.archiveSession(missing)
    #expect(model.sessionActionError != nil)
    let file = activeRoot.appendingPathComponent("bucket/success.jsonl")
    try writeNavigationSession(at: file, id: "success", cwd: "/tmp/project")
    await model.reloadSessions()
    let session = try #require(model.sessions.first)

    await model.archiveSession(session)

    #expect(model.sessionActionError == nil)
}

@MainActor
@Test func archivingANewSessionUsesTheControllerTranscriptPath() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-new-session-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let library = SessionLibrary(root: container.appendingPathComponent("sessions"))
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: library))
    await model.bootstrap()
    model.chooseProject(project)
    model.startNewSession(prompt: "Start")
    for _ in 0..<500 where model.activeSession?.sessionPath != "/tmp/fake.jsonl" {
        try await Task.sleep(for: .milliseconds(20))
    }
    let manager = try #require(model.processManager)
    #expect(model.activeSession?.sessionPath == "/tmp/fake.jsonl")
    #expect(await manager.handle(for: "/tmp/fake.jsonl") != nil)

    await model.archiveSession(navigationMetadata("/tmp/fake.jsonl"))

    #expect(model.route == .newSession)
    #expect(model.activeSession == nil)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") == nil)
    await manager.closeAll()
}

@MainActor
@Test func backgroundSessionActivityRemainsTrackedUntilItsTurnFinishes() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-background-activity-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "slow-turn")
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    model.chooseProject(project)
    model.startNewSession(prompt: "Start")
    for _ in 0..<100 where model.providerActivityCounts["test"] != 1 {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(model.providerActivityCounts["test"] == 1)
    model.openNewSession()
    #expect(model.activeSession == nil)
    #expect(model.route == .newSession)
    #expect(model.providerActivityCounts["test"] == 1)

    for _ in 0..<150 where model.providerActivityCounts["test"] != nil {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.providerActivityCounts["test"] == nil)
    if let manager = model.processManager {
        await manager.closeAll()
    }
}

@MainActor
@Test func reopeningManagedSessionReusesItsController() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-reused-controller-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    model.chooseProject(project)
    model.startNewSession(prompt: "Start")
    for _ in 0..<500 where model.activeSession?.sessionPath != "/tmp/fake.jsonl" {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(model.activeSession?.sessionPath == "/tmp/fake.jsonl")
    let original = try #require(model.activeSession)

    model.openNewSession()
    model.openSession(navigationMetadata("/tmp/fake.jsonl"))
    let reopened = try #require(model.activeSession)

    #expect(reopened === original)
    if let manager = model.processManager {
        await manager.closeAll()
    }
}

@MainActor
@Test func reopeningTheSameSessionBeforeItsInitialOpenStartsReusesItsController() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-rapid-reuse-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    let metadata = navigationMetadata("/tmp/fake.jsonl")

    model.openSession(metadata)
    let original = try #require(model.activeSession)
    model.openSession(metadata)

    #expect(model.activeSession === original)
    if let manager = model.processManager {
        await manager.closeAll()
    }
}

@MainActor
@Test func openingASessionWhileItsNewSessionOpenIsInFlightReusesItsController() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-new-session-race-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let release = container.appendingPathComponent("release")
    let executable = try makeNavigationExecutable(
        in: container,
        mode: "block-subagent-subscription",
        arguments: [release.path])
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    model.chooseProject(project)
    model.startNewSession(prompt: "Start")

    // The child parks on the last command of the open, so the controller knows its
    // path while `openNew` — and the indexing that follows it — is still in flight.
    for _ in 0..<500 where model.activeSession?.sessionPath != "/tmp/fake.jsonl" {
        try await Task.sleep(for: .milliseconds(20))
    }
    let original = try #require(model.activeSession)
    #expect(original.sessionPath == "/tmp/fake.jsonl")

    model.openSession(navigationMetadata("/tmp/fake.jsonl", cwd: project.path))

    #expect(model.activeSession === original)

    FileManager.default.createFile(atPath: release.path, contents: nil)
    for _ in 0..<500 where !original.draft.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(original.draft.isEmpty)
    #expect(model.activeSession === original)
    let manager = try #require(model.processManager)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") != nil)
    await manager.closeAll()
}

@MainActor
@Test func failedOpenExistingWithoutSessionPathIsNotReusedOnRetry() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-failed-open-retry-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "crash-after-negotiation")
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    let metadata = navigationMetadata("/tmp/fake.jsonl")
    let manager = try #require(model.processManager)

    model.openSession(metadata)
    let failed = try #require(model.activeSession)
    for _ in 0..<100 where failed.sessionPath != nil || !isFailed(failed.runtimeState) {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(failed.sessionPath == nil)
    #expect(isFailed(failed.runtimeState))

    model.openNewSession()
    model.openSession(metadata)
    let retried = try #require(model.activeSession)

    #expect(retried !== failed)
    #expect(model.providerActivityCounts.isEmpty)
    #expect(await manager.handle(for: metadata.path) == nil)
    await manager.closeAll()
}

@MainActor
@Test func unexpectedExitUpdatesARetainedBackgroundController() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-background-exit-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "background-exit")
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    model.openSession(navigationMetadata("/tmp/fake.jsonl", cwd: project.path))
    for _ in 0..<100 where model.activeSession?.sessionPath != "/tmp/fake.jsonl" {
        try await Task.sleep(for: .milliseconds(20))
    }
    let original = try #require(model.activeSession)
    let manager = try #require(model.processManager)
    for _ in 0..<100 where original.runtimeState != .streaming {
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(original.runtimeState == .streaming)

    model.openNewSession()
    for _ in 0..<100 where !original.isRecoveryPresented {
        try await Task.sleep(for: .milliseconds(20))
    }
    let isStopped = switch original.runtimeState {
    case .stopped:
        true
    default:
        false
    }

    #expect(original.isRecoveryPresented)
    #expect(isStopped)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") == nil)
    #expect(model.activeSession == nil)
    await manager.closeAll()
}

@MainActor
@Test func archivingAPendingStreamingSessionClosesAndRemovesActivity() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-pending-archive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "pending-streaming")
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    let metadata = navigationMetadata("/tmp/fake.jsonl", cwd: project.path)
    let manager = try #require(model.processManager)

    model.openSession(metadata)
    await model.archiveSession(metadata)
    try await Task.sleep(for: .milliseconds(500))

    #expect(await manager.handle(for: metadata.path) == nil)
    #expect(model.providerActivityCounts.isEmpty)
    await manager.closeAll()
}

@MainActor
@Test func mutationLockDetachesBeforeCloseAndBlocksReentrantActions() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-mutation-lock-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container, mode: "slow-exit")
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let library = SessionLibrary(root: container.appendingPathComponent("sessions"))
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: library))
    await model.bootstrap()
    model.chooseProject(project)
    model.startNewSession(prompt: "Start")
    for _ in 0..<100 where model.activeSession?.sessionPath != "/tmp/fake.jsonl" {
        try await Task.sleep(for: .milliseconds(20))
    }
    let manager = try #require(model.processManager)
    let metadata = navigationMetadata("/tmp/fake.jsonl")
    let started = ContinuousClock.now

    let mutation = Task { await model.archiveSession(metadata) }
    for _ in 0..<100 where !model.isSessionMutationInFlight {
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(model.isSessionMutationInFlight)
    #expect(started.duration(to: .now) < .milliseconds(500))
    #expect(model.activeSession == nil)
    #expect(model.route == .newSession)
    model.openSession(navigationMetadata("/tmp/other.jsonl"))
    model.openSettings()
    model.startNewSession(prompt: "Reentrant")
    #expect(model.activeSession == nil)
    #expect(model.route == .newSession)
    await model.restoreSession(navigationMetadata("/tmp/other.jsonl"))
    #expect(model.sessionActionError == nil)

    await mutation.value

    #expect(!model.isSessionMutationInFlight)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") == nil)
    model.openSettings()
    #expect(model.route == .settings)
    await manager.closeAll()
}

@MainActor
private func navigationDependencies<Locator: OmpLocating>(
    ompLocator: Locator,
    sessionLibrary: SessionLibrary,
    sessionSearch: SessionSearchService = SessionSearchService()
) -> AppDependencies {
    let defaults = appModelTestDefaults()
    return AppDependencies(
        ompLocator: ompLocator,
        sessionLibrary: sessionLibrary,
        sessionSearch: sessionSearch,
        recentProjectStore: RecentProjectStore(defaults: defaults),
        startupTiming: appModelTestTiming,
        makeProcessManager: { executable in
            SessionProcessManager(executable: executable)
        },
        makeSettingsModel: { _ in
            SettingsViewModel(service: OmpConfigService(
                runner: AppModelTestConfigRunner()))
        },
        makeProviderModel: { _ in
            providerTestModel(providers: [
                ProviderLoginProvider(
                    id: "cursor",
                    name: "Cursor",
                    isAvailable: true,
                    isAuthenticated: true),
            ])
        },
        makeComposerControls: stubAppComposerControlsFactory,
        makeUpdateChecker: stubUpdateCheckerFactory)
}

private func navigationMetadata(_ path: String, cwd: String = "/tmp/Project") -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: cwd,
        title: "Session",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 10,
        status: .complete)
}

private func isFailed(_ state: SessionRuntimeState) -> Bool {
    if case .failed = state { return true }
    return false
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

func makeNavigationExecutable(
    in directory: URL,
    mode: String = "basic",
    arguments: [String] = []
) throws -> URL {
    let repository = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixture = repository
        .appendingPathComponent("OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py")
    let executable = directory.appendingPathComponent("fake-omp")
    let extraArguments = arguments.map { " \"\($0)\"" }.joined()
    let wrapper = """
    #!/bin/sh
    exec /usr/bin/python3 "\(fixture.path)" "\(mode)"\(extraArguments)
    """
    try Data(wrapper.utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)
    return executable
}

private struct MissingOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpLocation { .notFound }
}

private struct FixedOmpLocator: OmpLocating {
    let executableURL: URL

    func locate(preferredURL: URL?) async -> OmpLocation {
        .found(OmpInstallation(executableURL: executableURL, version: "test"))
    }
}

@MainActor
@Test func bootstrapRequiresProviderWhenOMPHasNoAuthenticatedProvider() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()

    #expect(model.route == .providerSetup)
}

@MainActor
@Test func bootstrapOpensNewSessionWhenAProviderIsAuthenticated() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()

    #expect(model.route == .newSession)
}

@MainActor
@Test func openProvidersSelectsTheRequestedWorkspaceSection() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    model.openProviders(.usage)

    #expect(model.route == .providers(.usage))
    #expect(model.providerModel?.selectedSection == .usage)
}

@MainActor
@Test func openProviderUsageSelectsUsageRoute() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    model.openProviders(.usage)

    #expect(model.route == .providers(.usage))
}

@MainActor
@Test func refreshProvidersIfNeededRefreshesComposerControlsOnForeground() async {
    let catalog = CountingAppComposerCatalog()
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(
        providerModel: providerModel,
        makeComposerControls: { _ in
            ComposerControlsModel(catalog: catalog, defaults: StubAppComposerDefaults())
        }))

    await model.bootstrap()
    let loadsAfterBootstrap = await catalog.loadCount
    #expect(loadsAfterBootstrap >= 1)

    await model.refreshProvidersIfNeeded()
    #expect(await catalog.loadCount == loadsAfterBootstrap + 1)
}

@MainActor
@Test func refreshProvidersIfNeededRefreshesAtFiveMinutesButNotBefore() async {
    let clock = ProviderRefreshClock(date: Date(timeIntervalSince1970: 100))
    let usageService = FakeUsageService(snapshot: .empty)
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [
            ProviderLoginProvider(
                id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
        ]),
        usageService: usageService,
        openURL: { _ in },
        now: { clock.date },
        formatTime: { _ in "4:00 PM" })
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    await model.refreshProvidersIfNeeded()
    #expect(await usageService.loadCount == 1)

    clock.date = Date(timeIntervalSince1970: 400)
    await model.refreshProvidersIfNeeded()
    #expect(await usageService.loadCount == 2)
}

@MainActor
@Test func openProvidersKeepsSettingsDataIntact() async throws {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    model.openSettings()
    let settingsModel = try #require(model.settingsModel)
    let settingsCount = settingsModel.settingCount
    model.openProviders(.connections)

    #expect(model.route == .providers(.connections))
    #expect(settingsModel.settingCount == settingsCount)
}

@MainActor
@Test func settingsRouteStaysOnSettingsWhenProvidersAreAvailable() async throws {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()
    model.openSettings()

    #expect(model.route == .settings)
    #expect(model.providerModel != nil)
}

@MainActor
@Test func providerDiscoveryFailureKeepsRequiredSetupVisible() async {
    let providerModel = providerTestModel(
        providers: [],
        providerError: FakeProviderError.discoveryFailed)
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    await model.bootstrap()

    #expect(model.route == .providerSetup)
}

@MainActor
@Test func bootstrapSelectsProviderSetupWhileUsageIsStillLoading() async {
    let usageGate = LoadGate()
    let usageService = FakeUsageService(snapshot: .empty)
    await usageService.enqueueLoadGate(usageGate)
    let providerModel = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [
            ProviderLoginProvider(
                id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false),
        ]),
        usageService: usageService,
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))

    let bootstrap = Task { await model.bootstrap() }
    await usageGate.waitForStart()
    for _ in 0..<20 { await Task.yield() }

    #expect(model.route == .providerSetup)
    await usageGate.release()
    await bootstrap.value
}

@MainActor
@Test func replacingProviderModelWaitsForItsShutdown() async {
    let shutdownGate = LoadGate()
    let firstService = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false)],
        shutdownGate: shutdownGate)
    let firstModel = ProviderManagementViewModel(
        providerService: firstService,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let secondModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let models = ProviderModelQueue(models: [firstModel, secondModel])
    let model = AppModel(dependencies: testDependencies(
        ompLocator: SequentialOmpLocator(installations: [testInstallation, testInstallation]),
        makeProviderModel: { _ in models.next() }))
    await model.bootstrap()

    let replacement = Task { await model.useOmp(at: URL(filePath: "/tmp/replacement-omp")) }
    for _ in 0..<20 { await Task.yield() }

    #expect(model.providerModel === firstModel)
    #expect(await firstService.shutdownCount == 1)
    await shutdownGate.release()
    await replacement.value
    #expect(model.providerModel === secondModel)
}

@MainActor
@Test func failedInstallWaitsForProviderModelShutdownBeforeClearing() async {
    let shutdownGate = LoadGate()
    let providerService = FakeProviderService(
        providers: [ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: false)],
        shutdownGate: shutdownGate)
    let providerModel = ProviderManagementViewModel(
        providerService: providerService,
        usageService: FakeUsageService(snapshot: .empty),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    let model = AppModel(dependencies: testDependencies(
        ompLocator: SequentialOmpLocator(installations: [testInstallation, nil]),
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()

    let failedInstall = Task { await model.useOmp(at: URL(filePath: "/tmp/missing-omp")) }
    for _ in 0..<20 { await Task.yield() }

    #expect(model.providerModel === providerModel)
    #expect(await providerService.shutdownCount == 1)
    await shutdownGate.release()
    await failedInstall.value
    #expect(model.providerModel == nil)
    #expect(model.route == .setup)
}

@MainActor
@Test func cancelledOmpInspectionPreservesTheInstalledWorkspace() async throws {
    let inspectionGate = LoadGate()
    let locator = InstalledThenCancelledOmpLocator(gate: inspectionGate)
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(
        ompLocator: locator,
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()
    let installation = try #require(model.installation)
    let processManager = try #require(model.processManager)
    let settingsModel = try #require(model.settingsModel)
    let route = model.route

    let inspection = Task {
        await model.useOmp(at: URL(filePath: "/tmp/cancelled-omp"))
    }
    await inspectionGate.waitForStart()
    inspection.cancel()
    await inspection.value

    #expect(model.installation == installation)
    #expect(model.processManager === processManager)
    #expect(model.settingsModel === settingsModel)
    #expect(model.providerModel === providerModel)
    #expect(model.route == route)
    #expect(model.setupError == nil)

    await processManager.closeAll()
}

private struct InstalledOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpLocation {
        .found(testInstallation)
    }
}

private let testInstallation = OmpInstallation(
    executableURL: URL(filePath: "/tmp/omp"),
    version: "test")

private actor SequentialOmpLocator: OmpLocating {
    private var installations: [OmpInstallation?]

    init(installations: [OmpInstallation?]) {
        self.installations = installations
    }

    func locate(preferredURL: URL?) async -> OmpLocation {
        guard !installations.isEmpty else { return .notFound }
        return installations.removeFirst().map(OmpLocation.found) ?? .notFound
    }
}

private actor InstalledThenCancelledOmpLocator: OmpLocating {
    private let gate: LoadGate
    private var isInitialLookup = true

    init(gate: LoadGate) {
        self.gate = gate
    }

    func locate(preferredURL: URL?) async throws -> OmpLocation {
        if isInitialLookup {
            isInitialLookup = false
            return .found(testInstallation)
        }
        await gate.started()
        while !Task.isCancelled { await Task.yield() }
        throw CancellationError()
    }
}

@MainActor
private final class ProviderModelQueue {
    private var models: [ProviderManagementViewModel]

    init(models: [ProviderManagementViewModel]) {
        self.models = models
    }

    func next() -> ProviderManagementViewModel {
        models.removeFirst()
    }
}

@MainActor
private func testDependencies(
    providerModel: ProviderManagementViewModel,
    makeComposerControls: @escaping @MainActor @Sendable (URL) -> ComposerControlsModel = stubAppComposerControlsFactory
) -> AppDependencies {
    testDependencies(
        ompLocator: InstalledOmpLocator(),
        makeProviderModel: { _ in providerModel },
        makeComposerControls: makeComposerControls)
}

@MainActor
private func testDependencies<Locator: OmpLocating>(
    ompLocator: Locator,
    makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel,
    makeComposerControls: @escaping @MainActor @Sendable (URL) -> ComposerControlsModel = stubAppComposerControlsFactory
) -> AppDependencies {
    let defaults = appModelTestDefaults()
    return AppDependencies(
        ompLocator: ompLocator,
        sessionLibrary: SessionLibrary(root: URL(
            filePath: "/tmp/10x-provider-tests-empty",
            directoryHint: .isDirectory)),
        sessionSearch: SessionSearchService(),
        recentProjectStore: RecentProjectStore(defaults: defaults),
        startupTiming: appModelTestTiming,
        makeProcessManager: { executable in
            SessionProcessManager(executable: executable)
        },
        makeSettingsModel: { _ in
            SettingsViewModel(service: OmpConfigService(
                runner: AppModelTestConfigRunner()))
        },
        makeProviderModel: makeProviderModel,
        makeComposerControls: makeComposerControls,
        makeUpdateChecker: stubUpdateCheckerFactory)
}

private let appModelTestTiming = StartupTiming(
    minimumVisibility: .zero,
    timeout: .seconds(10),
    updateCheckDeadline: .milliseconds(50),
    sleep: { duration in
        guard duration == .seconds(10) else { return }
        try await ContinuousClock().sleep(for: .seconds(60))
    })

private struct AppModelTestConfigRunner: OmpConfigRunning {
    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "path"] {
            return Data("/tmp/omp/config.json\n".utf8)
        }
        return Data(#"{"autoResume":{"value":false,"type":"boolean","description":"Automatically resume"}}"#.utf8)
    }
}

private func appModelTestDefaults() -> UserDefaults {
    let suiteName = "AppModelNavigationTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("[Tests:AppModelNavigation] Unable to create defaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private final class ProviderRefreshClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDate: Date

    init(date: Date) {
        storedDate = date
    }

    var date: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedDate
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedDate = newValue
        }
    }
}

let stubAppComposerControlsFactory: @MainActor @Sendable (URL) -> ComposerControlsModel = { _ in
    ComposerControlsModel(
        catalog: StubAppComposerCatalog(),
        defaults: StubAppComposerDefaults())
}

/// These navigation and shell-snapshot fixtures build `AppDependencies` directly rather
/// than through `StartupFixture`/`makeStartupDependencies`, so without this they would
/// fall back to `AppDependencies`'s own default `makeUpdateChecker`, which stands up a
/// real Sparkle-backed `UpdateController` against `Bundle.main` and asks it to check for
/// updates on every `bootstrap()` call. A stub answering "nothing new" keeps these tests
/// from touching Sparkle or the network at all.
let stubUpdateCheckerFactory: @MainActor @Sendable (
    @escaping @MainActor () async -> Void) -> any UpdateChecking = { _ in
    stubUpdateCheckerReportingNoUpdate()
}

private actor StubAppComposerCatalog: ComposerCatalogLoading {
    func load() async throws -> ComposerCatalogSnapshot {
        ComposerCatalogSnapshot(
            models: [],
            selected: nil,
            thinkingLevel: nil,
            fastModeEnabled: false,
            fastModeActive: false)
    }

    func shutdown() async {}
}

private actor CountingAppComposerCatalog: ComposerCatalogLoading {
    private(set) var loadCount = 0

    func load() async throws -> ComposerCatalogSnapshot {
        loadCount += 1
        return ComposerCatalogSnapshot(
            models: [],
            selected: nil,
            thinkingLevel: nil,
            fastModeEnabled: false,
            fastModeActive: false)
    }

    func shutdown() async {}
}

private actor StubAppComposerDefaults: ComposerDefaultPersisting {
    func setDefaultModel(provider: String, modelID: String) async throws {}
    func setDefaultThinkingLevel(_ level: String) async throws {}
}

@MainActor
@Test func openingSearchRefreshesSessions() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-open-search-\(UUID().uuidString)", directoryHint: .isDirectory)
    let bucket = directory.appending(path: "project", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = bucket.appending(path: "session.jsonl")
    try Data("""
    {"type":"session","id":"open-search-session","cwd":"/tmp/Prime Radiant","timestamp":"2026-08-24T12:00:00.000Z","version":3,"title":"Open search refresh"}
    {"type":"message","id":"message-1","timestamp":"2026-08-24T12:01:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Search refresh marker"}]}}

    """.utf8).write(to: session)

    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: SessionLibrary(root: directory),
        sessionSearch: SessionSearchService(
            databaseURL: directory.appending(path: "SearchIndex-v1.sqlite"))))

    model.openSearch()
    for _ in 0..<40 where model.sessions.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(model.isSearchPresented)
    #expect(model.sessions.map(\.title) == ["Open search refresh"])
}
