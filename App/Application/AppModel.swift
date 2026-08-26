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
    @ObservationIgnored private var sessionChangeTask: Task<Void, Never>?
    @ObservationIgnored private var warmExitTask: Task<Void, Never>?
    @ObservationIgnored private var providerUsageTask: Task<Void, Never>?
    @ObservationIgnored private var fallbackTasks: [Task<Void, Never>] = []
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
        await replaceWorkspaceRuntime(with: locatedInstallation)
        guard !Task.isCancelled else { return }
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
        guard startupState.phase == .recovery,
              let attemptID = startupState.attemptID
        else { return }
        let operation = startupOperation
        startupOperation = nil
        operation?.task.cancel()
        await cancelUnfinishedStartupWork(attemptID: attemptID)
        await operation?.task.value
        startupState.requestHandoff(attemptID: attemptID)
        startFallbackLoadsForStoppedStages()
    }

    func workspaceDidOpen() async {
        guard !hasStartedWarmRetention else { return }
        hasStartedWarmRetention = true
        await processManager?.beginWarmRetention(
            primaryProjectDirectory: selectedProjectURL?.path)
    }

    func handleMemoryPressure() async {
        guard let processManager else { return }
        let evicted = await processManager.evictWarmClients()
        let canceled = await processManager.cancelWarmings()
        guard !evicted.isEmpty || !canceled.isEmpty,
              startupState.phase == .preparing,
              let attemptID = startupState.attemptID
        else { return }
        let operation = startupOperation
        startupOperation = nil
        operation?.task.cancel()
        await operation?.task.value
        startupState.markStopped(.recentProjects, attemptID: attemptID)
        startupState.enterRecovery(attemptID: attemptID)
    }

    func shutdown() async {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        let startup = startupOperation
        startupOperation = nil
        startup?.task.cancel()
        let sessionChanges = sessionChangeTask
        sessionChangeTask = nil
        sessionChanges?.cancel()
        let warmExits = warmExitTask
        warmExitTask = nil
        warmExits?.cancel()
        let activeExits = exitTask
        exitTask = nil
        activeExits?.cancel()
        let usage = providerUsageTask
        providerUsageTask = nil
        usage?.cancel()
        let fallbacks = fallbackTasks
        fallbackTasks.removeAll()
        fallbacks.forEach { $0.cancel() }

        await providerModel?.shutdown()
        await processManager?.closeAll()
        await startup?.task.value
        await sessionChanges?.value
        await warmExits?.value
        await activeExits?.value
        await usage?.value
        for fallback in fallbacks { await fallback.value }
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

    private func cancelUnfinishedStartupWork(attemptID: UUID) async {
        _ = await processManager?.cancelWarmings()
        guard startupState.attemptID == attemptID,
              startupState.status(of: .runtime) != .ready
        else { return }
        let provider = providerModel
        providerModel = nil
        providerUsages = []
        let usage = providerUsageTask
        providerUsageTask = nil
        usage?.cancel()
        await provider?.shutdown()
        await usage?.value
    }

    private func replaceWorkspaceRuntime(with located: OmpInstallation?) async {
        await stopProviderUsage()
        let oldProvider = providerModel
        let oldManager = processManager
        await oldProvider?.shutdown()
        await oldManager?.closeAll()
        guard !Task.isCancelled else { return }
        await stopProcessWatchers()
        guard !Task.isCancelled else { return }

        guard let located else {
            installation = nil
            processManager = nil
            settingsModel = nil
            providerModel = nil
            providerUsages = []
            route = .setup
            return
        }

        let manager = dependencies.makeProcessManager(located.executableURL.path)
        let settings = dependencies.makeSettingsModel(located.executableURL)
        let provider = dependencies.makeProviderModel(located.executableURL)
        installation = located
        processManager = manager
        settingsModel = settings
        providerModel = provider
        providerUsages = []
        setupError = nil
        route = .providerSetup
        await restartProcessWatchers(for: manager)
        guard !Task.isCancelled else { return }
        startProviderUsage(for: provider)
        await provider.loadProviders()
        guard !Task.isCancelled, providerModel === provider else { return }
        route = provider.hasAuthenticatedProvider ? .newSession : .providerSetup
    }

    private func startFallbackLoadsForStoppedStages() {
        let stages = StartupStageID.allCases.filter {
            startupState.status(of: $0) == .stopped
        }
        var tasks: [Task<Void, Never>] = []
        if stages.contains(.sessions) {
            tasks.append(Task { [weak self] in
                guard let self else { return }
                async let active = self.dependencies.sessionLibrary.listAll()
                async let archived = self.dependencies.sessionLibrary.listArchived()
                let loaded = await (active, archived)
                guard self.startupState.phase == .handoff else { return }
                self.sessions = loaded.0
                self.archivedSessions = loaded.1
                self.startSessionChangeWatching()
            })
        }
        if stages.contains(.settings) {
            tasks.append(Task { [weak self] in
                _ = await self?.settingsModel?.load()
            })
        }
        if stages.contains(.runtime) {
            tasks.append(Task { [weak self] in
                await self?.loadProviderFallback()
            })
        }
        fallbackTasks = tasks
    }

    private func loadProviderFallback() async {
        guard startupState.phase == .handoff,
              let installation
        else { return }
        let provider = providerModel ?? dependencies.makeProviderModel(installation.executableURL)
        if providerModel == nil {
            providerModel = provider
            startProviderUsage(for: provider)
        }
        await provider.loadProviders()
        guard startupState.phase == .handoff, providerModel === provider else { return }
        route = provider.hasAuthenticatedProvider ? .newSession : .providerSetup
    }

    private func startSessionChangeWatching() {
        guard sessionChangeTask == nil else { return }
        let library = dependencies.sessionLibrary
        sessionChangeTask = Task { [weak self] in
            for await _ in library.changes {
                guard let self, !Task.isCancelled else { return }
                await self.reloadSessions()
                await self.reloadArchivedSessions()
            }
        }
    }

    private func startProviderUsage(for provider: ProviderManagementViewModel) {
        providerUsageTask = Task { [weak self, weak provider] in
            guard let provider else { return }
            await provider.loadUsage()
            guard let self, self.providerModel === provider else { return }
            self.providerUsages = provider.railProviders
        }
    }

    private func stopProviderUsage() async {
        let usage = providerUsageTask
        providerUsageTask = nil
        usage?.cancel()
        await usage?.value
    }

    private func restartProcessWatchers(for processManager: SessionProcessManager) async {
        await stopProcessWatchers()
        exitTask = Task { [weak self] in
            for await exit in processManager.unexpectedExits {
                guard let self, !Task.isCancelled,
                      self.activeSession?.sessionPath == exit.sessionPath
                else { continue }
                self.activeSession?.handleUnexpectedExit(
                    code: exit.code,
                    stderrTail: exit.stderrTail)
            }
        }
        warmExitTask = Task { [weak self] in
            for await _ in processManager.unexpectedWarmExits {
                guard let self, !Task.isCancelled else { return }
                await self.handleWarmExit(from: processManager)
            }
        }
    }

    private func stopProcessWatchers() async {
        let active = exitTask
        exitTask = nil
        active?.cancel()
        let warm = warmExitTask
        warmExitTask = nil
        warm?.cancel()
        await active?.value
        await warm?.value
    }

    private func handleWarmExit(from manager: SessionProcessManager) async {
        guard processManager === manager,
              startupState.phase == .preparing,
              let attemptID = startupState.attemptID
        else { return }
        let operation = startupOperation
        startupOperation = nil
        operation?.task.cancel()
        _ = await manager.cancelWarmings()
        await operation?.task.value
        guard startupState.attemptID == attemptID,
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
