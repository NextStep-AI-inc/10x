import Foundation
import Observation
import OmpKit

@MainActor
@Observable
final class AppModel {
    private struct StartupOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    private struct FallbackOperation {
        let id: UUID
        let attemptID: UUID
        let generation: Int
        let lifecycleGeneration: Int
        let tasks: [Task<Void, Never>]
    }

    private struct ProviderUsageOperation {
        let id: UUID
        let lifecycleGeneration: Int
        let task: Task<Void, Never>
    }

    private enum StartupAttemptError: Error {
        case timeout
        case settingsUnavailable
    }

    private enum StartupPreparation: Sendable {
        case ready
        case missingOmp
    }

    var route: AppRoute = .setup
    var installation: OmpInstallation?
    var selectedProjectURL: URL?
    var setupError: String?
    var sessions: [SessionMetadata] = []
    var archivedSessions: [SessionMetadata] = []
    var pendingDeletion: SessionDeletionRequest?
    var sessionActionError: String?
    var providerUsages: [ProviderUsageProvider] = []
    var isSearchPresented = false
    private(set) var settingsFocusTarget: SettingsFocusTarget?
    private(set) var isSessionMutationInFlight = false
    private(set) var activeSession: SessionController?
    private(set) var processManager: SessionProcessManager?
    private(set) var settingsModel: SettingsViewModel?
    let ideRegistry: IDERegistry
    let idePreferenceStore: IDEPreferenceStore
    let fileOpenService: FileOpenService
    private(set) var providerModel: ProviderManagementViewModel?
    private(set) var startupState = StartupState()

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    @ObservationIgnored private var archivedReloadGeneration = 0
    @ObservationIgnored private var startupOperation: StartupOperation?
    @ObservationIgnored private var continueOperation: StartupOperation?
    @ObservationIgnored private var sessionChangeTask: Task<Void, Never>?
    @ObservationIgnored private var sessionChangeGeneration = 0
    @ObservationIgnored private var warmExitTask: Task<Void, Never>?
    @ObservationIgnored private var processWatcherGeneration = 0
    @ObservationIgnored private var providerUsageOperation: ProviderUsageOperation?
    @ObservationIgnored private var fallbackOperation: FallbackOperation?
    @ObservationIgnored private(set) var fallbackGeneration = 0
    @ObservationIgnored private(set) var lifecycleGeneration = 0
    @ObservationIgnored private(set) var isShuttingDown = false
    @ObservationIgnored private var workspaceRuntimeReplacementCount = 0
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var hasStartedWarmRetention = false

    init(
        dependencies: AppDependencies = .live,
        ideRegistry: IDERegistry = .init(),
        preferenceDefaults: UserDefaults = .standard,
        fileOpenService: FileOpenService = .live
    ) {
        self.dependencies = dependencies
        self.ideRegistry = ideRegistry
        idePreferenceStore = IDEPreferenceStore(defaults: preferenceDefaults, registry: ideRegistry)
        self.fileOpenService = fileOpenService
        startMemoryPressureMonitoring()
    }

    func bootstrap() async {
        guard !isShuttingDown else { return }
        if let operation = startupOperation {
            await operation.task.value
            return
        }
        guard startupState.attemptID == nil else { return }
        let id = UUID()
        startupState.beginAttempt(id: id)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runStartupAttempt(id: id, stages: Set(StartupStageID.allCases))
        }
        startupOperation = StartupOperation(id: id, task: task)
        await task.value
        if startupOperation?.id == id { startupOperation = nil }
    }

    func retryStartup() async {
        guard !isShuttingDown else { return }
        guard startupState.phase == .recovery else { return }
        if let operation = startupOperation {
            await operation.task.value
            return
        }
        let id = UUID()
        let stages = startupState.beginRetry(id: id)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runStartupAttempt(id: id, stages: stages)
        }
        startupOperation = StartupOperation(id: id, task: task)
        await task.value
        if startupOperation?.id == id { startupOperation = nil }
    }

    func useOmp(at url: URL) async {
        let locatedInstallation: OmpInstallation?
        do {
            locatedInstallation = try await dependencies.ompLocator.locate(preferredURL: url)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            return
        }
        guard await replaceWorkspaceRuntime(with: locatedInstallation),
              !Task.isCancelled,
              !isShuttingDown
        else { return }
        setupError = locatedInstallation == nil
            ? OmpExecutableLocator.inspectionErrorDescription(for: url)
            : nil
    }

    func chooseProject(_ url: URL) {
        guard !isSessionMutationInFlight else { return }
        let project = url.standardizedFileURL
        selectedProjectURL = project
        dependencies.recentProjectStore.recordSelection(project)
        activeSession = nil
        route = .newSession
    }

    func openSettings(focus: SettingsFocusTarget? = nil) {
        guard !isSessionMutationInFlight else { return }
        settingsFocusTarget = focus
        route = .settings
        Task { await settingsModel?.load() }
    }

    func consumeSettingsFocus() {
        settingsFocusTarget = nil
    }

    func openProviders(_ section: ProviderWorkspaceSection) {
        providerModel?.selectedSection = section
        route = .providers(section)
    }

    func refreshProvidersIfNeeded() async {
        await providerModel?.refreshIfStale()
    }

    func openNewSession() {
        guard !isSessionMutationInFlight else { return }
        activeSession = nil
        route = .newSession
    }

    func openArchivedSessions() {
        guard !isSessionMutationInFlight else { return }
        route = .archivedSessions
        Task { await reloadArchivedSessions() }
    }

    func completeProviderSetup() {
        guard providerModel?.hasAuthenticatedProvider == true else { return }
        route = .newSession
    }

    func openSearch() {
        guard !isSessionMutationInFlight else { return }
        isSearchPresented = true
    }

    func closeSearch() {
        isSearchPresented = false
    }

    func openSearchResult(_ result: SearchResult) {
        guard !isSessionMutationInFlight else { return }
        guard let metadata = sessions.first(where: { $0.path == result.sessionPath }) else { return }
        closeSearch()
        openSession(metadata)
    }

    func openSession(_ metadata: SessionMetadata) {
        guard !isSessionMutationInFlight else { return }
        if !metadata.cwd.isEmpty {
            selectedProjectURL = URL(filePath: metadata.cwd, directoryHint: .isDirectory)
                .standardizedFileURL
        }
        guard let processManager else { return }
        let controller = SessionController(processManager: processManager)
        activeSession = controller
        route = .session(metadata.path)
        Task { await controller.openExisting(metadata) }
    }

    func startNewSession(prompt: String) {
        guard !isSessionMutationInFlight else { return }
        guard let processManager, let selectedProjectURL else { return }
        let controller = SessionController(processManager: processManager)
        controller.draft = prompt
        activeSession = controller
        route = .session("new:\(UUID().uuidString)")
        Task {
            await controller.openNew(projectURL: selectedProjectURL)
            await controller.sendPrompt()
            await reloadSessions()
        }
    }

    func reloadSessions() async {
        sessions = await dependencies.sessionLibrary.listAll()
    }

    func reloadArchivedSessions() async {
        archivedReloadGeneration &+= 1
        let generation = archivedReloadGeneration
        let sessions = await dependencies.sessionLibrary.listArchived()
        guard generation == archivedReloadGeneration else { return }
        archivedSessions = sessions
    }

    func continueToWorkspace() async {
        if let operation = continueOperation {
            await operation.task.value
            return
        }
        guard startupState.phase == .recovery,
              let attemptID = startupState.attemptID,
              !isShuttingDown,
              workspaceRuntimeReplacementCount == 0
        else { return }
        let id = UUID()
        let generation = lifecycleGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performContinueToWorkspace(
                id: id,
                attemptID: attemptID,
                lifecycleGeneration: generation)
        }
        continueOperation = StartupOperation(id: id, task: task)
        await task.value
        if continueOperation?.id == id { continueOperation = nil }
    }

    private func performContinueToWorkspace(
        id: UUID,
        attemptID: UUID,
        lifecycleGeneration generation: Int
    ) async {
        let operation = startupOperation
        startupOperation = nil
        operation?.task.cancel()
        await cancelUnfinishedStartupWork(
            attemptID: attemptID,
            lifecycleGeneration: generation)
        guard isCurrentContinueOperation(
            id: id,
            attemptID: attemptID,
            lifecycleGeneration: generation)
        else {
            await operation?.task.value
            return
        }
        await operation?.task.value
        guard isCurrentContinueOperation(
            id: id,
            attemptID: attemptID,
            lifecycleGeneration: generation)
        else { return }
        startupState.requestHandoff(attemptID: attemptID)
        guard startupState.phase == .handoff else { return }
        startFallbackLoadsForStoppedStages(
            attemptID: attemptID,
            lifecycleGeneration: generation)
    }

    func workspaceDidOpen() async {
        guard !hasStartedWarmRetention,
              !isShuttingDown,
              let processManager,
              let selectedProjectURL
        else { return }
        hasStartedWarmRetention = true
        await processManager.beginWarmRetention(
            primaryProjectDirectory: selectedProjectURL.path)
    }

    func handleMemoryPressure() async {
        guard !isShuttingDown, let processManager else { return }
        let evicted = await processManager.evictWarmClients()
        guard !isShuttingDown, self.processManager === processManager else { return }
        let canceled = await processManager.cancelWarmings()
        guard !isShuttingDown,
              self.processManager === processManager,
              !evicted.isEmpty || !canceled.isEmpty,
              startupState.phase == .preparing,
              let attemptID = startupState.attemptID
        else { return }
        let operation = startupOperation
        startupOperation = nil
        operation?.task.cancel()
        await operation?.task.value
        guard !isShuttingDown,
              self.processManager === processManager,
              startupState.attemptID == attemptID,
              startupState.phase == .preparing
        else { return }
        startupState.markStopped(.recentProjects, attemptID: attemptID)
        startupState.enterRecovery(attemptID: attemptID)
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        lifecycleGeneration &+= 1
        let continuation = continueOperation
        continueOperation = nil
        continuation?.task.cancel()
        let fallbacks = fallbackOperation
        fallbackOperation = nil
        fallbacks?.tasks.forEach { $0.cancel() }
        let startup = startupOperation
        startupOperation = nil
        startup?.task.cancel()

        let sessionChanges = sessionChangeTask
        sessionChangeTask = nil
        sessionChangeGeneration &+= 1
        sessionChanges?.cancel()
        let warmExits = warmExitTask
        warmExitTask = nil
        processWatcherGeneration &+= 1
        warmExits?.cancel()
        let activeExits = exitTask
        exitTask = nil
        activeExits?.cancel()
        let usage = providerUsageOperation
        providerUsageOperation = nil
        usage?.task.cancel()

        let provider = providerModel
        let manager = processManager
        async let providerShutdown: Void = provider?.shutdown() ?? ()
        async let processShutdown: Void = manager?.closeAll() ?? ()
        await providerShutdown
        await processShutdown

        await continuation?.task.value
        if let fallbacks {
            for fallback in fallbacks.tasks { await fallback.value }
        }
        await startup?.task.value
        await sessionChanges?.value
        await warmExits?.value
        await activeExits?.value
        await usage?.task.value
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

    func dismissSessionActionError() {
        sessionActionError = nil
    }

    func archiveSession(_ metadata: SessionMetadata) async {
        guard beginSessionMutation() else { return }
        defer { endSessionMutation() }
        await mutateActive(
            paths: [metadata.path],
            action: "archive",
            subject: sessionDisplayName(metadata)) {
                await dependencies.sessionLibrary.archive(paths: [metadata.path])
            }
    }

    func archiveProject(_ group: ProjectSessionGroup) async {
        guard beginSessionMutation() else { return }
        defer { endSessionMutation() }
        let paths = group.sessions.map(\.path)
        await mutateActive(
            paths: paths,
            action: "archive",
            subject: "\(group.displayName) sessions") {
                await dependencies.sessionLibrary.archive(paths: paths)
            }
    }

    func restoreSession(_ metadata: SessionMetadata) async {
        guard beginSessionMutation() else { return }
        defer { endSessionMutation() }
        invalidateArchivedSessionReloads()
        await finish(
            await dependencies.sessionLibrary.restore(paths: [metadata.path]),
            action: "restore",
            subject: sessionDisplayName(metadata))
    }

    func restoreProject(_ group: ProjectSessionGroup) async {
        guard beginSessionMutation() else { return }
        defer { endSessionMutation() }
        invalidateArchivedSessionReloads()
        await finish(
            await dependencies.sessionLibrary.restore(paths: group.sessions.map(\.path)),
            action: "restore",
            subject: "\(group.displayName) sessions")
    }

    func confirmDeletion() async {
        guard let request = pendingDeletion, beginSessionMutation() else { return }
        defer { endSessionMutation() }
        pendingDeletion = nil
        invalidateArchivedSessionReloads()
        await closeActiveSessionIfNeeded(paths: request.paths)
        await finish(
            await dependencies.sessionLibrary.delete(paths: request.paths),
            action: "delete",
            subject: request.errorSubject)
    }

    private func mutateActive(
        paths: [String],
        action: String,
        subject: String,
        operation: () async -> SessionMutationReport
    ) async {
        invalidateArchivedSessionReloads()
        await closeActiveSessionIfNeeded(paths: paths)
        await finish(await operation(), action: action, subject: subject)
    }

    private func closeActiveSessionIfNeeded(paths: [String]) async {
        let activePath = activeSession?.sessionPath
        let routePath: String? = if case .session(let path) = route { path } else { nil }
        let matchingPath: String? = if let activePath {
            paths.contains(activePath) ? activePath : nil
        } else if let routePath, paths.contains(routePath) {
            routePath
        } else {
            nil
        }
        guard let matchingPath else { return }
        let processManager = processManager
        activeSession = nil
        if routePath != nil { route = .newSession }
        await processManager?.close(sessionPath: matchingPath)
    }

    private func finish(
        _ report: SessionMutationReport,
        action: String,
        subject: String
    ) async {
        sessionActionError = nil
        if !report.failures.isEmpty {
            let count = report.failures.count
            let unchangedFiles = count == 1
                ? "file remains unchanged."
                : "files remain unchanged."
            sessionActionError = "Could not \(action) \(subject). \(count) session \(unchangedFiles)"
        }
        await reloadSessions()
        await reloadArchivedSessions()
    }

    private func invalidateArchivedSessionReloads() {
        archivedReloadGeneration &+= 1
    }

    private func beginSessionMutation() -> Bool {
        guard !isSessionMutationInFlight else { return false }
        isSessionMutationInFlight = true
        return true
    }

    private func endSessionMutation() {
        isSessionMutationInFlight = false
    }

    private func sessionDisplayName(_ metadata: SessionMetadata) -> String {
        metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
    }

    private func runStartupAttempt(id: UUID, stages: Set<StartupStageID>) async {
        let timing = dependencies.startupTiming
        let (runtimeLocated, runtimeLocatedContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let minimumVisibility = Task {
            for await _ in runtimeLocated { break }
            try Task.checkCancellation()
            try await timing.sleep(timing.minimumVisibility)
        }

        do {
            let preparation = try await withWatchdog(attemptID: id) {
                try await self.prepareStartup(
                    attemptID: id,
                    stages: stages,
                    runtimeLocated: {
                        runtimeLocatedContinuation.yield()
                        runtimeLocatedContinuation.finish()
                    })
            }
            try await withTaskCancellationHandler {
                try await minimumVisibility.value
            } onCancel: {
                minimumVisibility.cancel()
            }
            try checkStartupAttempt(id)
            switch preparation {
            case .ready, .missingOmp:
                startupState.requestHandoff(attemptID: id)
            }
        } catch {
            runtimeLocatedContinuation.finish()
            minimumVisibility.cancel()
            _ = await minimumVisibility.result
            guard !Task.isCancelled,
                  startupState.attemptID == id,
                  startupState.phase == .preparing
            else { return }
            startupState.enterRecovery(attemptID: id)
        }
    }

    private func withWatchdog<Value: Sendable>(
        attemptID: UUID,
        _ operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let timing = dependencies.startupTiming
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await timing.sleep(timing.timeout)
                throw StartupAttemptError.timeout
            }
            do {
                guard let first = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return first
            } catch {
                group.cancelAll()
                await cancelUnfinishedStartupWork(attemptID: attemptID)
                throw error
            }
        }
    }

    private func prepareStartup(
        attemptID: UUID,
        stages: Set<StartupStageID>,
        runtimeLocated: @escaping @Sendable () -> Void
    ) async throws -> StartupPreparation {
        if stages.contains(.runtime) {
            let hasRuntime = try await prepareRuntime(
                attemptID: attemptID,
                runtimeLocated: runtimeLocated)
            if !hasRuntime { return .missingOmp }
        } else {
            runtimeLocated()
        }

        try checkStartupAttempt(attemptID)
        try await withThrowingTaskGroup(of: Void.self) { group in
            if stages.contains(.settings) {
                group.addTask {
                    try await self.prepareSettings(attemptID: attemptID)
                }
            }
            if stages.contains(.sessions) || stages.contains(.recentProjects) {
                group.addTask {
                    try await self.prepareSessionsAndRecentProjects(
                        attemptID: attemptID,
                        stages: stages)
                }
            }
            try await group.waitForAll()
        }
        try checkStartupAttempt(attemptID)
        return .ready
    }

    private func prepareRuntime(
        attemptID: UUID,
        runtimeLocated: @escaping @Sendable () -> Void
    ) async throws -> Bool {
        startupState.markLoading(.runtime, attemptID: attemptID)
        let located = try await dependencies.ompLocator.locate(preferredURL: nil)
        runtimeLocated()
        try checkStartupAttempt(attemptID)

        guard let located else {
            await stopProviderUsage()
            let oldProvider = providerModel
            let oldManager = processManager
            await oldProvider?.shutdown()
            await oldManager?.closeAll()
            try checkStartupAttempt(attemptID)
            await stopProcessWatchers()
            try checkStartupAttempt(attemptID)
            installation = nil
            processManager = nil
            settingsModel = nil
            providerModel = nil
            providerUsages = []
            route = .setup
            return false
        }

        let isSameExecutable = installation?.executableURL.standardizedFileURL
            == located.executableURL.standardizedFileURL
        let manager: SessionProcessManager
        let settings: SettingsViewModel
        let provider: ProviderManagementViewModel

        if isSameExecutable {
            manager = processManager
                ?? dependencies.makeProcessManager(located.executableURL.path)
            settings = settingsModel
                ?? dependencies.makeSettingsModel(located.executableURL)
            provider = providerModel
                ?? dependencies.makeProviderModel(located.executableURL)
            try checkStartupAttempt(attemptID)
        } else {
            await stopProviderUsage()
            let oldProvider = providerModel
            let oldManager = processManager
            await oldProvider?.shutdown()
            await oldManager?.closeAll()
            try checkStartupAttempt(attemptID)
            manager = dependencies.makeProcessManager(located.executableURL.path)
            settings = dependencies.makeSettingsModel(located.executableURL)
            provider = dependencies.makeProviderModel(located.executableURL)
        }

        try checkStartupAttempt(attemptID)
        installation = located
        processManager = manager
        settingsModel = settings
        providerModel = provider
        setupError = nil
        route = .providerSetup
        await restartProcessWatchers(for: manager)
        try checkStartupAttempt(attemptID)
        await stopProviderUsage()
        try checkStartupAttempt(attemptID)
        startProviderUsage(for: provider)
        await provider.loadProviders()
        try checkStartupAttempt(attemptID)
        guard providerModel === provider else { throw CancellationError() }
        route = provider.hasAuthenticatedProvider ? .newSession : .providerSetup
        startupState.markReady(.runtime, attemptID: attemptID)
        return true
    }

    private func prepareSettings(attemptID: UUID) async throws {
        try checkStartupAttempt(attemptID)
        startupState.markLoading(.settings, attemptID: attemptID)
        guard let settingsModel else {
            throw StartupAttemptError.settingsUnavailable
        }
        let isReady = await settingsModel.load()
        try checkStartupAttempt(attemptID)
        guard isReady else { throw StartupAttemptError.settingsUnavailable }
        startupState.markReady(.settings, attemptID: attemptID)
    }

    private func prepareSessionsAndRecentProjects(
        attemptID: UUID,
        stages: Set<StartupStageID>
    ) async throws {
        if stages.contains(.sessions) {
            try checkStartupAttempt(attemptID)
            startupState.markLoading(.sessions, attemptID: attemptID)
            async let active = dependencies.sessionLibrary.listAll()
            async let archived = dependencies.sessionLibrary.listArchived()
            let loaded = await (active, archived)
            try checkStartupAttempt(attemptID)
            sessions = loaded.0
            archivedSessions = loaded.1
            startSessionChangeWatching()
            startupState.markReady(.sessions, attemptID: attemptID)
        }

        guard stages.contains(.recentProjects) else { return }
        try checkStartupAttempt(attemptID)
        startupState.markLoading(.recentProjects, attemptID: attemptID)
        let projects = dependencies.recentProjectStore.rankedProjects(sessions: sessions)
        if selectedProjectURL == nil {
            selectedProjectURL = projects.first
        }
        guard let processManager else { throw CancellationError() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for project in projects {
                group.addTask {
                    _ = try await processManager.warm(projectDirectory: project.path)
                }
            }
            try await group.waitForAll()
        }
        try checkStartupAttempt(attemptID)
        startupState.markReady(.recentProjects, attemptID: attemptID)
    }

    private func cancelUnfinishedStartupWork(
        attemptID: UUID,
        lifecycleGeneration expectedLifecycleGeneration: Int? = nil
    ) async {
        _ = await processManager?.cancelWarmings()
        guard !Task.isCancelled,
              expectedLifecycleGeneration.map({ $0 == lifecycleGeneration }) ?? true,
              !isShuttingDown,
              startupState.attemptID == attemptID,
              startupState.status(of: .runtime) != .ready
        else { return }
        let provider = providerModel
        providerModel = nil
        providerUsages = []
        let usage = providerUsageOperation
        providerUsageOperation = nil
        usage?.task.cancel()
        await provider?.shutdown()
        await usage?.task.value
    }

    private func replaceWorkspaceRuntime(with located: OmpInstallation?) async -> Bool {
        guard !isShuttingDown else { return false }
        workspaceRuntimeReplacementCount += 1
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        defer { workspaceRuntimeReplacementCount -= 1 }
        await cancelWorkspacePreparationForLifecycleChange()
        guard isCurrentLifecycle(generation) else { return false }
        await stopProviderUsage()
        guard isCurrentLifecycle(generation) else { return false }
        let oldProvider = providerModel
        let oldManager = processManager
        await oldProvider?.shutdown()
        guard isCurrentLifecycle(generation) else { return false }
        await oldManager?.closeAll()
        guard isCurrentLifecycle(generation) else { return false }
        await stopProcessWatchers()
        guard isCurrentLifecycle(generation) else { return false }

        guard let located else {
            installation = nil
            processManager = nil
            settingsModel = nil
            providerModel = nil
            providerUsages = []
            route = .setup
            return true
        }

        let manager = dependencies.makeProcessManager(located.executableURL.path)
        let settings = dependencies.makeSettingsModel(located.executableURL)
        let provider = dependencies.makeProviderModel(located.executableURL)
        guard isCurrentLifecycle(generation) else {
            await provider.shutdown()
            await manager.closeAll()
            return false
        }
        installation = located
        processManager = manager
        settingsModel = settings
        providerModel = provider
        providerUsages = []
        setupError = nil
        route = .providerSetup
        await restartProcessWatchers(for: manager)
        guard isCurrentLifecycle(generation),
              processManager === manager,
              providerModel === provider
        else { return false }
        startProviderUsage(for: provider)
        await provider.loadProviders()
        guard isCurrentLifecycle(generation),
              processManager === manager,
              providerModel === provider
        else { return false }
        route = provider.hasAuthenticatedProvider ? .newSession : .providerSetup
        return true
    }

    private func cancelWorkspacePreparationForLifecycleChange() async {
        let continuation = continueOperation
        continueOperation = nil
        continuation?.task.cancel()
        let fallback = fallbackOperation
        fallbackOperation = nil
        fallback?.tasks.forEach { $0.cancel() }

        await continuation?.task.value
        if let fallback {
            for task in fallback.tasks { await task.value }
        }
    }

    private func isCurrentLifecycle(_ generation: Int) -> Bool {
        !Task.isCancelled
            && !isShuttingDown
            && lifecycleGeneration == generation
    }

    private func isCurrentContinueOperation(
        id: UUID,
        attemptID: UUID,
        lifecycleGeneration: Int
    ) -> Bool {
        !Task.isCancelled
            && !isShuttingDown
            && self.lifecycleGeneration == lifecycleGeneration
            && continueOperation?.id == id
            && startupState.attemptID == attemptID
            && startupState.phase == .recovery
    }

    private func isCurrentFallback(
        id: UUID,
        attemptID: UUID,
        generation: Int,
        lifecycleGeneration: Int
    ) -> Bool {
        !Task.isCancelled
            && !isShuttingDown
            && self.lifecycleGeneration == lifecycleGeneration
            && fallbackOperation?.id == id
            && fallbackOperation?.attemptID == attemptID
            && fallbackOperation?.generation == generation
            && fallbackOperation?.lifecycleGeneration == lifecycleGeneration
            && startupState.attemptID == attemptID
            && startupState.phase == .handoff
    }

    private func isCurrentSessionChange(generation: Int) -> Bool {
        !Task.isCancelled
            && !isShuttingDown
            && sessionChangeTask != nil
            && sessionChangeGeneration == generation
    }

    private func startFallbackLoadsForStoppedStages(
        attemptID: UUID,
        lifecycleGeneration: Int
    ) {
        guard fallbackOperation == nil,
              !isShuttingDown,
              self.lifecycleGeneration == lifecycleGeneration,
              startupState.attemptID == attemptID,
              startupState.phase == .handoff
        else { return }
        let stages = StartupStageID.allCases.filter {
            startupState.status(of: $0) == .stopped
        }
        let id = UUID()
        fallbackGeneration &+= 1
        let generation = fallbackGeneration
        var tasks: [Task<Void, Never>] = []
        if stages.contains(.sessions) {
            tasks.append(Task { [weak self] in
                guard let self else { return }
                guard self.isCurrentFallback(
                    id: id,
                    attemptID: attemptID,
                    generation: generation,
                    lifecycleGeneration: lifecycleGeneration)
                else { return }
                self.archivedReloadGeneration &+= 1
                let archivedGeneration = self.archivedReloadGeneration
                async let active = self.dependencies.sessionLibrary.listAll()
                async let archived = self.dependencies.sessionLibrary.listArchived()
                let loaded = await (active, archived)
                guard self.isCurrentFallback(
                    id: id,
                    attemptID: attemptID,
                    generation: generation,
                    lifecycleGeneration: lifecycleGeneration),
                      archivedGeneration == self.archivedReloadGeneration
                else { return }
                self.sessions = loaded.0
                self.archivedSessions = loaded.1
                self.startSessionChangeWatching()
            })
        }
        if stages.contains(.settings) {
            tasks.append(Task { [weak self] in
                guard let self,
                      self.isCurrentFallback(
                        id: id,
                        attemptID: attemptID,
                        generation: generation,
                        lifecycleGeneration: lifecycleGeneration),
                      let settings = self.settingsModel
                else { return }
                _ = await settings.load()
                guard self.isCurrentFallback(
                    id: id,
                    attemptID: attemptID,
                    generation: generation,
                    lifecycleGeneration: lifecycleGeneration),
                      self.settingsModel === settings
                else { return }
            })
        }
        if stages.contains(.runtime) {
            tasks.append(Task { [weak self] in
                await self?.loadProviderFallback(
                    id: id,
                    attemptID: attemptID,
                    generation: generation,
                    lifecycleGeneration: lifecycleGeneration)
            })
        }
        fallbackOperation = FallbackOperation(
            id: id,
            attemptID: attemptID,
            generation: generation,
            lifecycleGeneration: lifecycleGeneration,
            tasks: tasks)
    }

    private func loadProviderFallback(
        id: UUID,
        attemptID: UUID,
        generation: Int,
        lifecycleGeneration: Int
    ) async {
        guard isCurrentFallback(
            id: id,
            attemptID: attemptID,
            generation: generation,
            lifecycleGeneration: lifecycleGeneration),
              let installation
        else { return }
        let provider = providerModel ?? dependencies.makeProviderModel(installation.executableURL)
        if providerModel == nil {
            guard isCurrentFallback(
                id: id,
                attemptID: attemptID,
                generation: generation,
                lifecycleGeneration: lifecycleGeneration)
            else {
                await provider.shutdown()
                return
            }
            providerModel = provider
            startProviderUsage(for: provider)
        }
        await provider.loadProviders()
        guard isCurrentFallback(
            id: id,
            attemptID: attemptID,
            generation: generation,
            lifecycleGeneration: lifecycleGeneration),
              providerModel === provider
        else { return }
        route = provider.hasAuthenticatedProvider ? .newSession : .providerSetup
    }

    private func startSessionChangeWatching() {
        guard sessionChangeTask == nil else { return }
        sessionChangeGeneration &+= 1
        let generation = sessionChangeGeneration
        let library = dependencies.sessionLibrary
        sessionChangeTask = Task { [weak self] in
            for await _ in library.changes {
                guard let self,
                      self.isCurrentSessionChange(generation: generation)
                else { return }
                self.archivedReloadGeneration &+= 1
                let archivedGeneration = self.archivedReloadGeneration
                async let active = library.listAll()
                async let archived = library.listArchived()
                let loaded = await (active, archived)
                guard self.isCurrentSessionChange(generation: generation),
                      archivedGeneration == self.archivedReloadGeneration
                else { return }
                self.sessions = loaded.0
                self.archivedSessions = loaded.1
            }
        }
    }

    private func startProviderUsage(for provider: ProviderManagementViewModel) {
        guard providerUsageOperation == nil, !isShuttingDown else { return }
        let id = UUID()
        let lifecycleGeneration = self.lifecycleGeneration
        let task = Task { [weak self, weak provider] in
            guard let self,
                  let provider,
                  self.isCurrentProviderUsage(
                    id: id,
                    lifecycleGeneration: lifecycleGeneration,
                    provider: provider)
            else { return }
            await provider.loadUsage()
            guard self.isCurrentProviderUsage(
                id: id,
                lifecycleGeneration: lifecycleGeneration,
                provider: provider)
            else { return }
            self.providerUsages = provider.railProviders
        }
        providerUsageOperation = ProviderUsageOperation(
            id: id,
            lifecycleGeneration: lifecycleGeneration,
            task: task)
    }

    private func stopProviderUsage() async {
        let usage = providerUsageOperation
        providerUsageOperation = nil
        usage?.task.cancel()
        await usage?.task.value
    }

    private func isCurrentProviderUsage(
        id: UUID,
        lifecycleGeneration: Int,
        provider: ProviderManagementViewModel
    ) -> Bool {
        !Task.isCancelled
            && !isShuttingDown
            && self.lifecycleGeneration == lifecycleGeneration
            && providerUsageOperation?.id == id
            && providerUsageOperation?.lifecycleGeneration == lifecycleGeneration
            && providerModel === provider
    }

    private func restartProcessWatchers(for processManager: SessionProcessManager) async {
        await stopProcessWatchers()
        guard !Task.isCancelled,
              !isShuttingDown,
              self.processManager === processManager
        else { return }
        processWatcherGeneration &+= 1
        let generation = processWatcherGeneration
        exitTask = Task { [weak self] in
            for await exit in processManager.unexpectedExits {
                guard let self,
                      self.isCurrentProcessWatcher(
                        generation: generation,
                        processManager: processManager),
                      self.activeSession?.sessionPath == exit.sessionPath
                else { continue }
                self.activeSession?.handleUnexpectedExit(
                    code: exit.code,
                    stderrTail: exit.stderrTail)
            }
        }
        warmExitTask = Task { [weak self] in
            for await _ in processManager.unexpectedWarmExits {
                guard let self,
                      self.isCurrentProcessWatcher(
                        generation: generation,
                        processManager: processManager)
                else { return }
                await self.handleWarmExit(from: processManager)
            }
        }
    }

    private func stopProcessWatchers() async {
        processWatcherGeneration &+= 1
        let active = exitTask
        exitTask = nil
        active?.cancel()
        let warm = warmExitTask
        warmExitTask = nil
        warm?.cancel()
        await active?.value
        await warm?.value
    }

    private func isCurrentProcessWatcher(
        generation: Int,
        processManager: SessionProcessManager
    ) -> Bool {
        !Task.isCancelled
            && !isShuttingDown
            && processWatcherGeneration == generation
            && self.processManager === processManager
    }

    private func handleWarmExit(from manager: SessionProcessManager) async {
        guard !isShuttingDown,
              processManager === manager,
              startupState.phase == .preparing,
              let attemptID = startupState.attemptID
        else { return }
        let operation = startupOperation
        startupOperation = nil
        operation?.task.cancel()
        _ = await manager.cancelWarmings()
        await operation?.task.value
        guard !isShuttingDown,
              processManager === manager,
              startupState.attemptID == attemptID,
              startupState.phase == .preparing
        else { return }
        startupState.markStopped(.recentProjects, attemptID: attemptID)
        startupState.enterRecovery(attemptID: attemptID)
    }

    private func startMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleMemoryPressure()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private func checkStartupAttempt(_ id: UUID) throws {
        try Task.checkCancellation()
        guard startupState.attemptID == id,
              startupState.phase == .preparing
        else { throw CancellationError() }
    }
}
