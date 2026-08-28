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
    model.route = .onboarding(.installOmp)

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

    await model.archiveCurrentSession()

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
    await waitForManagedSession("/tmp/fake.jsonl", in: model)
    let manager = try #require(model.processManager)
    #expect(model.activeSession?.sessionPath == "/tmp/fake.jsonl")
    #expect(await manager.handle(for: "/tmp/fake.jsonl") != nil)

    await model.archiveSession(navigationMetadata("/tmp/fake.jsonl"))

    #expect(model.route == .newSession)
    #expect(model.activeSession == nil)
    #expect(model.sessionActivityRegistry.managedSessions.isEmpty)
    #expect(await manager.handle(for: "/tmp/fake.jsonl") == nil)
    await manager.closeAll()
}

@Suite @MainActor struct AppModelNavigationTests {
@Test func newSessionPinsPrimaryAfterStateAndBeforeFirstPrompt() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-primary-order-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let commandLog = container.appendingPathComponent("commands.log")
    let executable = try makeProviderRoutingExecutable(
        in: container,
        commandLog: commandLog)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let defaults = appModelTestDefaults()
    let coordinator = ProviderAccountCoordinator(
        primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults))
    await coordinator.useAccount(
        "acct_A",
        providerID: "openai-codex",
        scope: .allNewSessions,
        openSessionID: nil)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator }))
    await model.bootstrap()
    model.chooseProject(project)

    model.startNewSession(prompt: "Start")

    #expect(await navigationLog(commandLog, eventuallyContains: "prompt"))
    let lifecycle = try navigationCommands(in: commandLog).filter {
        $0 == "open"
            || $0 == "get_state"
            || $0.hasPrefix("pin_account:")
            || $0 == "prompt"
    }
    #expect(lifecycle == [
        "open",
        "get_state",
        "get_state",
        "pin_account:acct_A",
        "prompt",
    ])
    let controller = try #require(model.activeSession)
    #expect(coordinator.activeAccountRefs[controller.id] == "acct_A")
    let identity = try #require(model.activeSessionIdentityToken)
    #expect(identity == model.activeSession?.id)

    model.openNewSession()

    #expect(model.activeSessionIdentityToken == nil)
    if let manager = model.processManager { await manager.closeAll() }
}

@Suite @MainActor struct AppModelRemovalBarrierTests {
@Test func blocksNewAndResumedSessionControllerCreation() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-removal-barrier-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let coordinator = ProviderAccountCoordinator()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator }))
    await model.bootstrap()
    model.chooseProject(project)
    let target = providerAccountFixture(
        providerID: "openai-codex",
        ref: "acct_A",
        label: "Personal",
        order: 0)
    let remaining = providerAccountFixture(
        providerID: "openai-codex",
        ref: "acct_B",
        label: "Work",
        order: 1)
    let rpcGate = LoadGate()
    let removal = Task {
        try await coordinator.removeAccount(
            providerID: "openai-codex",
            accountRef: "acct_A",
            accounts: [target, remaining]
        ) {
            await rpcGate.started()
            await rpcGate.waitForRelease()
            return ProviderAccountRemovalResult(removed: true, accounts: [remaining])
        }
    }
    await rpcGate.waitForStart()

    model.startNewSession(prompt: "Blocked draft")
    model.openSession(navigationMetadata("/tmp/resumed.jsonl", cwd: project.path))

    #expect(model.activeSession == nil)
    #expect(coordinator.managedSessions.isEmpty)

    await rpcGate.release()
    _ = try await removal.value
    if let manager = model.processManager { await manager.closeAll() }
}
}

@MainActor

@Test func resumedSessionKeepsReportedAccountInsteadOfCurrentPrimary() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-resumed-primary-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let commandLog = container.appendingPathComponent("commands.log")
    let executable = try makeProviderRoutingExecutable(
        in: container,
        commandLog: commandLog,
        activeAccountRef: "acct_B")
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let defaults = appModelTestDefaults()
    let coordinator = ProviderAccountCoordinator(
        primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults))
    await coordinator.useAccount(
        "acct_A",
        providerID: "openai-codex",
        scope: .allNewSessions,
        openSessionID: nil)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator }))
    await model.bootstrap()

    model.openSession(navigationMetadata("/tmp/fake.jsonl", cwd: project.path))

    #expect(await navigationLog(commandLog, eventuallyContains: "set_subagent_subscription"))
    let controller = try #require(model.activeSession)
    #expect(controller.currentProviderAccountRef == "acct_B")
    #expect(coordinator.activeAccountRefs[controller.id] == "acct_B")
    #expect(coordinator.managedSessions.count == 1)
    #expect(coordinator.primaryAccountRef(providerID: "openai-codex") == "acct_A")
    #expect(try navigationCommands(in: commandLog).contains {
        $0.hasPrefix("set_session_provider_account:")
    } == false)
    if let manager = model.processManager { await manager.closeAll() }
}

@Test func unexpectedExitUnregistersTheRetainedControllerFromAccountRouting() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-account-exit-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeProviderRoutingExecutable(
        in: container,
        commandLog: container.appendingPathComponent("commands.log"),
        activeAccountRef: "acct_A",
        exitsAfterSubscription: true)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let coordinator = ProviderAccountCoordinator()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator }))
    await model.bootstrap()

    model.openSession(navigationMetadata("/tmp/fake.jsonl", cwd: project.path))

    await waitUntil("the exited session to present recovery and unregister") {
        model.activeSession?.isRecoveryPresented == true && coordinator.managedSessions.isEmpty
    }
    #expect(model.activeSession?.isRecoveryPresented == true)
    #expect(coordinator.managedSessions.isEmpty)
    if let manager = model.processManager { await manager.closeAll() }
}

@Test func newSessionUsesThePrimaryCapturedWhenCreationStarted() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-primary-snapshot-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let commandLog = container.appendingPathComponent("commands.log")
    let executable = try makeProviderRoutingExecutable(in: container, commandLog: commandLog)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let defaults = appModelTestDefaults()
    let coordinator = ProviderAccountCoordinator(
        primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults))
    await coordinator.useAccount(
        "acct_A",
        providerID: "openai-codex",
        scope: .allNewSessions,
        openSessionID: nil)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator }))
    await model.bootstrap()
    model.chooseProject(project)

    model.startNewSession(prompt: "Start")
    await coordinator.useAccount(
        "acct_B",
        providerID: "openai-codex",
        scope: .allNewSessions,
        openSessionID: nil)

    #expect(await navigationLog(commandLog, eventuallyContains: "prompt"))
    #expect(try navigationCommands(in: commandLog).filter {
        $0.hasPrefix("pin_account:")
    } == ["pin_account:acct_A"])
    #expect(coordinator.primaryAccountRef(providerID: "openai-codex") == "acct_B")
    if let manager = model.processManager { await manager.closeAll() }
}

@Test func newSessionExitBeforePathIndexingUnregistersItsRetainedController() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-new-account-exit-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeProviderRoutingExecutable(
        in: container,
        commandLog: container.appendingPathComponent("commands.log"),
        activeAccountRef: "acct_A",
        exitsAfterSubscription: true)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let coordinator = ProviderAccountCoordinator()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator }))
    await model.bootstrap()
    model.chooseProject(project)

    model.startNewSession(prompt: "Start")

    await waitUntil("the exited session to present recovery and unregister") {
        model.activeSession?.isRecoveryPresented == true && coordinator.managedSessions.isEmpty
    }
    #expect(model.activeSession?.isRecoveryPresented == true)
    #expect(coordinator.managedSessions.isEmpty)
    if let manager = model.processManager { await manager.closeAll() }
}
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
    await waitUntil("the background turn to start") {
        model.providerActivityCounts["test"] == 1
    }

    #expect(model.providerActivityCounts["test"] == 1)
    model.openNewSession()
    #expect(model.activeSession == nil)
    #expect(model.route == .newSession)
    #expect(model.providerActivityCounts["test"] == 1)

    await waitUntil("the background turn to finish") {
        model.providerActivityCounts["test"] == nil
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
    await waitForManagedSession("/tmp/fake.jsonl", in: model)
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
    await waitUntil("the session to report its failure") {
        failed.sessionPath == nil && isFailed(failed.runtimeState)
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
    await waitForManagedSession("/tmp/fake.jsonl", in: model)
    let original = try #require(model.activeSession)
    let manager = try #require(model.processManager)
    await waitUntil("the session to start streaming") {
        original.runtimeState == .streaming
    }

    #expect(original.runtimeState == .streaming)

    model.openNewSession()
    await waitUntil("recovery to be presented") { original.isRecoveryPresented }
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
    await waitForManagedSession("/tmp/fake.jsonl", in: model)
    let manager = try #require(model.processManager)
    let metadata = navigationMetadata("/tmp/fake.jsonl")

    let mutation = Task { await model.archiveSession(metadata) }
    await waitUntil("the mutation to take the session lock") {
        model.isSessionMutationInFlight
    }

    // The detach has to land before the close, and this pair proves exactly
    // that without timing the machine: archiveSession only returns once the
    // child is closed, so a mutation still in flight cannot have finished
    // closing — yet the session is already detached.
    #expect(model.isSessionMutationInFlight)
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

/// Waits until the model would hand back the *same* controller for `path`.
///
/// Deliberately not `activeSession?.sessionPath`: SessionController sets that
/// partway through `openNew` and then keeps awaiting (state, history, messages,
/// subscription), while AppModel indexes the path for reuse only once `openNew`
/// returns. A test that waits on the path alone can act inside that window and
/// get a second controller — and a second child — for one session.
@MainActor
private func waitForManagedSession(_ path: String, in model: AppModel) async {
    await waitUntil("session \(path) to be registered for reuse") {
        model.managedController(for: path) != nil
    }
}

@MainActor
private func navigationDependencies<Locator: OmpLocating>(
    ompLocator: Locator,
    sessionLibrary: SessionLibrary,
    sessionSearch: SessionSearchService = SessionSearchService(),
    makeProviderAccountCoordinator: @escaping @MainActor @Sendable () -> ProviderAccountCoordinator = {
        ProviderAccountCoordinator()
    },
    makeProviderModel: (
        @MainActor @Sendable (URL) -> ProviderManagementViewModel
    )? = nil
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
        makeProviderModel: makeProviderModel ?? { _ in
            providerTestModel(providers: [
                ProviderLoginProvider(
                    id: "cursor",
                    name: "Cursor",
                    isAvailable: true,
                    isAuthenticated: true),
            ])
        },
        makeComposerControls: stubAppComposerControlsFactory,
        makeProviderAccountCoordinator: makeProviderAccountCoordinator,
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

/// Models a session under the now-installed `ProviderAccountTieredRoutingBackend`
/// (`AppModel.init` → `ProviderAccountCoordinator.install`, wired in this
/// fix round): account changes arrive as `pin_account` commands over the
/// `tenx.provider-accounts.v1` extension channel, not as a direct
/// `set_session_provider_account` RPC command — the pre-Task-9 shape only
/// the abandoned fork's `omp` ever understood (see
/// `ProviderAccountExtensionBackend.swift`'s `ProviderAccountTieredRoutingBackend`
/// doc comment). Task 10 deleted that RPC command from `RpcCommand` entirely,
/// so this fixture no longer has a handler for it either — there is nothing
/// left that could send it.
///
/// The marker channel opens the same way `makeProviderAccountChannelExecutable`
/// (`SessionControllerTests.swift`) proved out: an `extension_ui_request`
/// right after `set_subagent_subscription` is answered, and each
/// `extension_ui_response` is answered by a *new* marker request whose
/// `placeholder` carries the reply, matched by the inner command `id` —
/// never the outer RPC frame `id`, which only identifies the open request
/// slot. `provider_account_changed` is emitted before that reply, on the
/// same frame-ordering guarantee the existing `makeProviderAccountExecutable`
/// fixture already relies on: `SessionController.consume` applies frames in
/// the order they arrive on the one `client.events` reader, so the session's
/// own `currentProviderAccountRef` is already updated by the time the
/// reply's continuation resumes `route()` and `applyThroughBackend` reads it
/// back via `synchronizeState`.
private func makeProviderRoutingExecutable(
    in directory: URL,
    commandLog: URL,
    activeAccountRef: String? = nil,
    exitsAfterSubscription: Bool = false
) throws -> URL {
    let executable = directory.appendingPathComponent("provider-routing-server.py")
    let logPath = String(reflecting: commandLog.path)
    let initialAccount = activeAccountRef.map(String.init(reflecting:)) ?? "None"
    let source = #"""
    #!/usr/bin/env python3
    import json
    import sys

    command_log = \#(logPath)
    initial_account = \#(initialAccount)

    MARKER = "tenx.provider-accounts.v1"
    channel_requests = 0

    def emit(value):
        print(json.dumps(value, separators=(",", ":")), flush=True)

    with open(command_log, "a", encoding="utf-8") as log:
        log.write("open\n")

    emit({"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864})
    for line in sys.stdin:
        command = json.loads(line)
        request_id = command.get("id")
        command_type = command.get("type")
        if command_type == "extension_ui_response":
            sent = json.loads(command.get("value", "{}"))
            inner_command = sent.get("command")
            if inner_command == "hello":
                # Task 10b fix round 1 added an unsolicited hello probe sent
                # over this same channel before any real command. The real
                # extension's hello handler is a pure query with no side
                # effect (OmpExtension/index.ts: case "hello": return
                # {contractVersion: 1} -- no log, no event, no sequence).
                # This fixture used to answer every extension_ui_response as
                # if it were pin_account regardless of which command was
                # actually sent, extracting accountRef blindly -- an empty
                # default for hello's empty params -- which logged a bogus
                # "pin_account:" line and emitted a provider_account_changed
                # event with an empty accountRef at sequence 1. Since events
                # below are also hardcoded to sequence 1, that bogus event
                # permanently blocked SessionController's monotonic-sequence
                # guard from ever accepting the real pin_account event that
                # followed (fix round 2 -- see task-10b-report.md).
                reply = json.dumps({"id": sent.get("id"), "ok": True, "data": {"contractVersion": 1}})
            else:
                account_ref = sent.get("params", {}).get("accountRef", "")
                with open(command_log, "a", encoding="utf-8") as log:
                    log.write("pin_account:" + account_ref + "\n")
                emit({"type":"provider_account_changed","providerId":"openai-codex","accountRef":account_ref,"reason":"manual","sequence":1})
                reply = json.dumps({"id": sent.get("id"), "ok": True, "data": {"applied": True}})
            channel_requests += 1
            emit({"type":"extension_ui_request","id":"acct-chan-" + str(channel_requests),"method":"input","title":MARKER,"placeholder":reply})
            continue
        logged = command_type
        with open(command_log, "a", encoding="utf-8") as log:
            log.write(logged + "\n")
        if command_type == "negotiate_protocol":
            data = {"protocolVersion":2}
        elif command_type == "get_state":
            data = {"model":{"id":"gpt-test","provider":"openai-codex"},"isStreaming":False,"sessionFile":"/tmp/fake.jsonl"}
            if initial_account is not None:
                data["activeProviderAccounts"] = {"openai-codex":initial_account}
        elif command_type == "get_messages_page":
            data = {"messages":[],"nextCursor":None}
        else:
            data = {}
        emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":data})
        if command_type == "set_subagent_subscription":
            channel_requests += 1
            emit({"type":"extension_ui_request","id":"acct-chan-" + str(channel_requests),"method":"input","title":MARKER})
            if \#(exitsAfterSubscription ? "True" : "False"):
                raise SystemExit(7)
        if command_type == "prompt":
            emit({"type":"agent_start"})
            emit({"type":"agent_end","messages":[],"isTerminal":True})
    """#
    try Data(source.utf8).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)
    return executable
}

private func navigationCommands(in url: URL) throws -> [String] {
    try String(contentsOf: url, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
}

@MainActor
private func navigationLog(_ url: URL, eventuallyContains expected: String) async -> Bool {
    await waitUntil("\(expected) in the navigation command log") {
        (try? navigationCommands(in: url).contains(expected)) == true
    }
}

private struct StubbedOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpLocation {
        .found(OmpInstallation(executableURL: URL(filePath: "/tmp/omp"), version: "test"))
    }
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

    #expect(model.route == .onboarding(.connectProvider))
}

@MainActor
@Test func bootstrapOpensNewSessionWhenAProviderIsAuthenticated() async {
    let providerModel = providerTestModel(providers: [
        ProviderLoginProvider(
            id: "cursor", name: "Cursor", isAvailable: true, isAuthenticated: true),
    ])
    let model = AppModel(dependencies: testDependencies(providerModel: providerModel))
    // A project is already selected, so this scenario is meant to reach the
    // workspace rather than the new project step onboarding also gates on.
    model.selectedProjectURL = URL(filePath: "/tmp/existing-project", directoryHint: .isDirectory)

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

    #expect(model.route == .onboarding(.connectProvider))
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

    #expect(model.route == .onboarding(.connectProvider))
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
    #expect(model.route == .onboarding(.installOmp))
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
    await waitUntil("the session list to load") { !model.sessions.isEmpty }

    #expect(model.isSearchPresented)
    #expect(model.sessions.map(\.title) == ["Open search refresh"])
}

@Suite @MainActor struct AppModelAccountDockTests {
/// Fix round 2 (task-9b): `capabilities:` below is a pre-Task-5 relic —
/// `ProviderManagementViewModel.refreshAccountUsage` no longer calls
/// `providerService.accountCapability(providerID:)` at all, so it can no
/// longer make a provider route. Capability now comes solely from
/// `ProviderAccountTier.detect(snapshot:extensionHello:)`
/// (`App/Providers/ProviderAccountTier.swift`), which needs a usage
/// snapshot carrying per-account identity — `.empty` always detects
/// `.providerOnly` (`snapshot.reports` is `[]`, so `hasPerAccountIdentity`
/// is always `false`), which silently disables every scope-satisfaction and
/// `useProviderAccount` assertion that depends on `.accountRouting`. Uses
/// `multiAccountUsageSnapshotFixture`, the same style of fixture
/// `ProviderManagementViewModelTests` uses for exactly this reason — this
/// suite just never got migrated when that one did.
///
/// Task 10b: accounts now derive from the snapshot
/// (`ProviderAccountUsageBackend`), not a per-account RPC a fake can hand
/// back arbitrary refs for, so `"acct_A"`/`"acct_B"` are no longer literal
/// strings a test can choose — they're `ProviderAccountRef.make`'s SHA256
/// output. Returns them alongside the model so call sites that cross-check
/// against `providerModel.dockProviders` (`accountScopeSatisfaction`,
/// `useProviderAccount`) compare against what the real read path actually
/// produces.
private func accountProviderModel() throws -> (
    model: ProviderManagementViewModel,
    accountARef: String,
    accountBRef: String
) {
    let accountA = AccountSnapshotEntry(accountID: "a1", email: "personal@example.com")
    let accountB = AccountSnapshotEntry(accountID: "a2", email: "work@example.com")
    let model = ProviderManagementViewModel(
        providerService: FakeProviderService(providers: [
            ProviderLoginProvider(
                id: "openai-codex",
                name: "ChatGPT",
                isAvailable: true,
                isAuthenticated: true),
        ]),
        usageService: FakeUsageService(snapshot: multiAccountUsageSnapshotFixture(
            providerID: "openai-codex",
            accounts: [accountA, accountB])),
        openURL: { _ in },
        now: { Date(timeIntervalSince1970: 100) })
    return (
        model,
        accountA.accountRef(providerID: "openai-codex"),
        accountB.accountRef(providerID: "openai-codex"))
}

private func emptyNavigationSessionLibrary() -> SessionLibrary {
    SessionLibrary(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("navigation-sessions-\(UUID().uuidString)"))
}

@Test func dockAccountStateMirrorsTheCoordinator() async throws {
    let coordinator = ProviderAccountCoordinator()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: emptyNavigationSessionLibrary(),
        makeProviderAccountCoordinator: { coordinator }))
    let session = DockAccountSession(providerID: "openai-codex", accountRef: "acct_A")
    coordinator.register(session)
    coordinator.update(sessionID: session.id, providerID: "openai-codex", isGenerating: true)

    #expect(model.accountGeneratingCounts == [
        ProviderAccountKey(providerID: "openai-codex", accountRef: "acct_A"): 1,
    ])
    #expect(model.pendingRemovalAccounts.isEmpty)
}

@Test func accountScopeSatisfactionReflectsSessionsAndPrimary() async throws {
    let suiteName = "tenx-dock-satisfaction-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let coordinator = ProviderAccountCoordinator(
        primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults))
    let (providerModel, accountARef, accountBRef) = try accountProviderModel()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: StubbedOmpLocator(),
        sessionLibrary: emptyNavigationSessionLibrary(),
        makeProviderAccountCoordinator: { coordinator },
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()
    await providerModel.load()
    let session = DockAccountSession(providerID: "openai-codex", accountRef: accountARef)
    coordinator.register(session)
    coordinator.update(sessionID: session.id, providerID: "openai-codex", isGenerating: false)
    await coordinator.useAccount(
        accountARef,
        providerID: "openai-codex",
        scope: .allNewSessions,
        openSessionID: nil)

    let satisfaction = model.accountScopeSatisfaction(openSessionID: session.id)
    let onAccountA = try #require(satisfaction[ProviderAccountKey(
        providerID: "openai-codex",
        accountRef: accountARef)])
    let onAccountB = try #require(satisfaction[ProviderAccountKey(
        providerID: "openai-codex",
        accountRef: accountBRef)])

    #expect(onAccountA.areAllScopesSatisfied)
    #expect(onAccountB == .none)
    if let manager = model.processManager { await manager.closeAll() }
}

@Test func manageAccountsOpensConnectionsFocusedOnTheProvider() async throws {
    let (providerModel, _, _) = try accountProviderModel()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: StubbedOmpLocator(),
        sessionLibrary: emptyNavigationSessionLibrary(),
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()

    model.manageProviderAccounts(providerID: "openai-codex")

    #expect(model.route == .providers(.connections))
    #expect(providerModel.selectedSection == .connections)
    #expect(providerModel.focusedConnectionsProviderID == "openai-codex")
    if let manager = model.processManager { await manager.closeAll() }
}

/// Fix round 2 (task-9b): rewritten to route a *real* `SessionController`
/// rather than the bare `DockAccountSession` fake used elsewhere in this
/// suite. Since fix round 1, `AppModel.init` always installs a live
/// `ProviderAccountTieredRoutingBackend` on whatever coordinator it's
/// handed (`ProviderAccountCoordinator.install`'s doc comment: idempotent,
/// and the only writer for a coordinator's routing backend) — so
/// `applyDirectly`, the direct-RPC path `DockAccountSession.setProviderAccount`
/// exists to model, is no longer reachable through any `AppModel`. Routing
/// now always resolves a session's channel-registry entry
/// (`ProviderAccountChannelRegistry`, populated only by
/// `SessionController.attachAccountChannel`) or its session file for the
/// pin-and-restart fallback (`ProviderAccountPinBackend`) — both of which a
/// bare in-memory fake structurally cannot have, and
/// `ProviderAccountPinBackendError.sessionFileUnavailable`'s doc comment is
/// explicit that hitting that gap is "a caller bug, not an expected
/// outcome" for any session the coordinator actually manages. So the old
/// assertion could never pass again after fix round 1 without either
/// faking out `restartSession` (impossible now that `install` is the sole,
/// AppModel-owned entry point — any coordinator handed to `AppModel` has
/// its restart closure overwritten regardless of what the test supplies)
/// or routing a session real enough to survive an actual pin+restart, which
/// is what this does, reusing the same marker-channel fixture
/// (`makeProviderRoutingExecutable`) the sibling `AppModelNavigationTests`
/// suite's tests already use for the identical reason.
@Test func useProviderAccountRoutesThroughTheCoordinator() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-dock-use-account-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let commandLog = container.appendingPathComponent("commands.log")
    let executable = try makeProviderRoutingExecutable(
        in: container,
        commandLog: commandLog,
        activeAccountRef: "acct_A")
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let coordinator = ProviderAccountCoordinator()
    let (providerModel, _, accountBRef) = try accountProviderModel()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions")),
        makeProviderAccountCoordinator: { coordinator },
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()
    model.openSession(navigationMetadata("/tmp/fake.jsonl", cwd: project.path))
    #expect(await navigationLog(commandLog, eventuallyContains: "set_subagent_subscription"))
    let controller = try #require(model.activeSession)
    #expect(controller.currentProviderAccountRef == "acct_A")
    await providerModel.load()

    await model.useProviderAccount(accountBRef, scope: .thisSession, openSessionID: controller.id)

    #expect(await navigationLog(commandLog, eventuallyContains: "pin_account:\(accountBRef)"))
    #expect(controller.currentProviderAccountRef == accountBRef)
    if let manager = model.processManager { await manager.closeAll() }
}

@Test func useProviderAccountIgnoresUnknownRefs() async throws {
    let coordinator = ProviderAccountCoordinator()
    let (providerModel, accountARef, _) = try accountProviderModel()
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: StubbedOmpLocator(),
        sessionLibrary: emptyNavigationSessionLibrary(),
        makeProviderAccountCoordinator: { coordinator },
        makeProviderModel: { _ in providerModel }))
    await model.bootstrap()
    await providerModel.load()
    let session = DockAccountSession(providerID: "openai-codex", accountRef: accountARef)
    coordinator.register(session)

    await model.useProviderAccount("acct_missing", scope: .thisSession, openSessionID: session.id)

    #expect(session.currentProviderAccountRef == accountARef)
    if let manager = model.processManager { await manager.closeAll() }
}

/// Fix round 1 (task-9b): the tiered routing backend and the live
/// `restartSession` closure were built but never actually installed on the
/// coordinator the running app uses, so the coordinator kept taking the
/// pre-existing direct-RPC path regardless of tier — exactly how the gap
/// this test guards against got there unnoticed in the first place.
/// `makeProviderAccountCoordinator: { coordinator }` hands `AppModel` this
/// test's own coordinator instance, so `coordinator.hasLiveRoutingBackend`
/// observes exactly what `AppModel.init` installed on it — the same
/// instance every session in this test would route through.
@Test func bootstrapInstallsALiveRoutingBackendOnTheCoordinator() async throws {
    let coordinator = ProviderAccountCoordinator()
    #expect(!coordinator.hasLiveRoutingBackend)

    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: StubbedOmpLocator(),
        sessionLibrary: emptyNavigationSessionLibrary(),
        makeProviderAccountCoordinator: { coordinator }))

    // Installed synchronously in `AppModel.init`, not deferred to
    // `bootstrap()` — true immediately, before bootstrap ever runs.
    #expect(coordinator.hasLiveRoutingBackend)

    await model.bootstrap()

    // Survives bootstrap unchanged — nothing in that path resets it.
    #expect(coordinator.hasLiveRoutingBackend)
    if let manager = model.processManager { await manager.closeAll() }
}
}

@MainActor
private final class DockAccountSession: ProviderAccountSession {
    let id = UUID()
    let providerID: String?
    var runtimeState: SessionRuntimeState = .idle
    private(set) var currentProviderAccountRef: String?
    private(set) var providerAccountSequence = 0

    init(providerID: String, accountRef: String) {
        self.providerID = providerID
        currentProviderAccountRef = accountRef
    }

    func setProviderAccount(
        providerID: String,
        accountRef: String
    ) async throws -> SetSessionProviderAccountResult {
        currentProviderAccountRef = accountRef
        providerAccountSequence += 1
        return SetSessionProviderAccountResult(
            account: ProviderAccountSummary(
                providerID: providerID,
                accountRef: accountRef,
                displayLabel: accountRef,
                connectionOrder: 0,
                availability: .available),
            sequence: providerAccountSequence)
    }
}
