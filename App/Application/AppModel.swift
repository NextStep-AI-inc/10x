import AppKit
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

    var route: AppRoute = .onboarding(.installOmp)
    var installation: OmpInstallation?
    var selectedProjectURL: URL?
    /// Set when OMP is installed but would not run, so setup can say that
    /// instead of reporting it as missing.
    var unrunnableOmpURL: URL?
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
    private(set) var composerControls: ComposerControlsModel?
    private(set) var startupState = StartupState()
    let sessionActivityRegistry = SessionActivityRegistry()

    var providerActivityCounts: [String: Int] {
        sessionActivityRegistry.activeCounts
    }

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    @ObservationIgnored private var archivedReloadGeneration = 0
    @ObservationIgnored private var composerControlsRefreshGeneration = 0
    @ObservationIgnored private var routeBeforeSettings: AppRoute?
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
    @ObservationIgnored private var managedSessions: [UUID: SessionController] = [:]
    @ObservationIgnored private var managedSessionPaths: [String: UUID] = [:]

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

    var sessionSearch: any SessionSearching {
        dependencies.sessionSearch
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

    func useOmp(at url: URL? = nil) async {
        let location: OmpLocation
        do {
            location = try await dependencies.ompLocator.locate(preferredURL: url)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            return
        }
        guard await replaceWorkspaceRuntime(with: location.installation),
              !Task.isCancelled,
              !isShuttingDown
        else { return }
        applySetupDiagnosis(location)
    }

    /// Setup needs to tell "nothing installed" apart from "installed but it
    /// would not run", so it can ask for the right thing.
    private func applySetupDiagnosis(_ location: OmpLocation) {
        switch location {
        case .found:
            unrunnableOmpURL = nil
        case .unrunnable(let url):
            unrunnableOmpURL = url
        case .notFound:
            unrunnableOmpURL = nil
        }
    }

    func chooseProject(_ url: URL) {
        guard !isSessionMutationInFlight else { return }
        let project = url.standardizedFileURL
        selectedProjectURL = project
        dependencies.recentProjectStore.recordSelection(project)
        clearActiveSession()
        detachComposerControlsAndRefresh()
        route = .newSession
    }

    /// Every project 10x remembers for listing (the rail, the composer's
    /// project flyout, onboarding) — wider than the two `rankedProjects`
    /// warms a client for at startup. Always includes `selectedProjectURL`,
    /// even before a selection lands in the store (e.g. the moment
    /// `chooseProject` sets it, before `recordSelection` has been read
    /// back).
    var knownProjectURLs: [URL] {
        var urls = dependencies.recentProjectStore.knownProjects()
        if let selectedProjectURL {
            let standardized = selectedProjectURL.standardizedFileURL
            if !urls.contains(where: { $0.path == standardized.path }) {
                urls.insert(standardized, at: 0)
            }
        }
        return urls
    }

    /// Every requirement the workspace does not yet satisfy, in order.
    func unmetRequirements() -> [OnboardingStep] {
        OnboardingStep.unmet(
            installation: installation,
            hasAuthenticatedProvider: providerModel?.hasAuthenticatedProvider == true,
            selectedProjectURL: selectedProjectURL)
    }

    /// The requirement to ask for now.
    func firstUnmetRequirement() -> OnboardingStep? {
        unmetRequirements().first
    }

    /// Routes to the first unmet requirement, or to the workspace. Replaces
    /// eight scattered decisions and preserves their force-to-`newSession`
    /// semantics: every caller runs before the splash hands off, or inside a
    /// runtime replacement that already discarded managed sessions.
    func gateRoute() {
        route = firstUnmetRequirement().map(AppRoute.onboarding) ?? .newSession
    }

    /// Records a project chosen during onboarding.
    ///
    /// Deliberately not `chooseProject`: that ends with `route = .newSession`,
    /// so the first selection would leave onboarding and no second folder
    /// could be added. There is no active session to tear down here.
    func recordOnboardingProject(_ url: URL) {
        let project = url.standardizedFileURL
        selectedProjectURL = project
        dependencies.recentProjectStore.recordSelection(project)
    }

    func chooseNewProject() {
        guard !isSessionMutationInFlight else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Project"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        chooseProject(url)
    }

    func openSettings(focus: SettingsFocusTarget? = nil) {
        guard !isSessionMutationInFlight else { return }
        if route != .settings {
            routeBeforeSettings = route
        }
        settingsFocusTarget = focus
        route = .settings
        Task { await settingsModel?.load() }
    }

    func leaveSettings() {
        guard !isSessionMutationInFlight else { return }
        guard route == .settings else { return }
        settingsFocusTarget = nil
        let destination = routeBeforeSettings ?? .newSession
        routeBeforeSettings = nil
        switch destination {
        case .onboarding, .settings:
            route = .newSession
        default:
            route = destination
        }
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
        await refreshComposerControls()
    }

    func openNewSession() {
        guard !isSessionMutationInFlight else { return }
        clearActiveSession()
        detachComposerControlsAndRefresh()
        route = .newSession
    }

    func openArchivedSessions() {
        guard !isSessionMutationInFlight else { return }
        route = .archivedSessions
        Task { await reloadArchivedSessions() }
    }

    func completeProviderSetup() {
        gateRoute()
        Task { await refreshComposerControls() }
    }

    func openSearch() {
        guard !isSessionMutationInFlight else { return }
        isSearchPresented = true
        Task { await reloadSessions() }
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
        if let controller = managedController(for: metadata.path) {
            composerControls?.detachActiveSession()
            activeSession = controller
            route = .session(metadata.path)
            composerControls?.attachActiveSession(controller)
            return
        }
        let controller = makeSessionController(
            processManager: processManager,
            intendedSessionPath: metadata.path)
        activeSession = controller
        route = .session(metadata.path)
        composerControls?.detachActiveSession()
        Task { [weak self, controller] in
            guard let self else { return }
            await controller.openExisting(metadata)
            guard self.managedSessions[controller.id] === controller else {
                controller.stopActivityTracking()
                await processManager.close(sessionPath: controller.sessionPath ?? metadata.path)
                return
            }
            guard controller.sessionPath != nil else {
                self.removeManagedSession(controller)
                return
            }
            self.indexManagedSessionPath(for: controller)
            guard self.activeSession === controller else { return }
            self.composerControls?.attachActiveSession(controller)
        }
    }

    func startNewSession(prompt: String, attachments: [ComposerAttachment] = []) {
        guard !isSessionMutationInFlight else { return }
        guard let processManager, let selectedProjectURL else { return }
        let controller = makeSessionController(processManager: processManager)
        controller.draft = prompt
        controller.attachments = attachments
        composerControls?.detachActiveSession()
        // omp does not name the session until the child is up, so the route
        // carries a placeholder until `openNew` reports the real path.
        let placeholderRoute = AppRoute.session("new:\(UUID().uuidString)")
        route = placeholderRoute
        let selection = composerControls?.spawnSelection
        activeSession = controller
        Task { [weak self, controller, selectedProjectURL, selection] in
            guard let self else { return }
            let fastOutcome = await controller.openNew(
                projectURL: selectedProjectURL,
                selection: selection)
            guard self.managedSessions[controller.id] === controller else {
                controller.stopActivityTracking()
                if let sessionPath = controller.sessionPath {
                    await processManager.close(sessionPath: sessionPath)
                }
                return
            }
            guard let sessionPath = controller.sessionPath else {
                self.removeManagedSession(controller)
                return
            }
            self.indexManagedSessionPath(for: controller)
            // Without this the rail can never mark the session the user is
            // looking at, and reopening it from the rail would spawn a second
            // child for a session that is already running here.
            if self.activeSession === controller, self.route == placeholderRoute {
                self.route = .session(sessionPath)
            }
            if self.activeSession === controller {
                if fastOutcome == .unsupported || fastOutcome == .failed {
                    await self.composerControls?.setFastMode(false, mode: .newSession)
                }
                if self.activeSession === controller {
                    self.composerControls?.attachActiveSession(controller)
                }
            }
            await controller.sendPrompt()
            await self.reloadSessions()
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
        let controls = composerControls
        let manager = processManager
        discardManagedSessions()
        async let providerShutdown: Void = provider?.shutdown() ?? ()
        async let composerShutdown: Void = controls?.shutdown() ?? ()
        async let processShutdown: Void = manager?.closeAll() ?? ()
        await providerShutdown
        await composerShutdown
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
        await closeManagedSessions(paths: request.paths)
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
        await closeManagedSessions(paths: paths)
        await finish(await operation(), action: action, subject: subject)
    }

    private func closeManagedSessions(paths: [String]) async {
        let routePath: String? = if case .session(let path) = route { path } else { nil }
        let indexedIDs = Set(paths.compactMap { managedSessionPaths[$0] })
        let matchingControllers = managedSessions.values.filter { controller in
            indexedIDs.contains(controller.id) || controller.sessionPath.map(paths.contains) == true
        }
        let matchingIDs = Set(matchingControllers.map(\.id))
        let matchingPaths = Set(matchingControllers.compactMap(\.sessionPath))
        let matchingIndexedPaths = Set(paths.filter { path in
            managedSessionPaths[path].map(matchingIDs.contains) == true
        })

        for controller in matchingControllers {
            removeManagedSession(controller)
        }
        let didRemoveActiveSession = if let activeSession {
            matchingIDs.contains(activeSession.id)
        } else {
            false
        }
        if didRemoveActiveSession {
            self.activeSession = nil
        }
        if didRemoveActiveSession || (routePath.map(paths.contains) == true) {
            activeSession = nil
            if routePath != nil {
                route = .newSession
            }
            detachComposerControlsAndRefresh()
        }

        let pathsToClose = if matchingPaths.union(matchingIndexedPaths).isEmpty,
                              let routePath,
                              paths.contains(routePath) {
            [routePath]
        } else {
            matchingPaths.union(matchingIndexedPaths).sorted()
        }
        for path in pathsToClose {
            await processManager?.close(sessionPath: path)
        }
    }

    private func detachComposerControlsAndRefresh() {
        composerControls?.detachActiveSession()
        composerControlsRefreshGeneration &+= 1
        let generation = composerControlsRefreshGeneration
        Task { await refreshComposerControlsIfCurrent(generation: generation) }
    }

    private func refreshComposerControlsIfCurrent(generation: Int) async {
        guard generation == composerControlsRefreshGeneration else { return }
        await refreshComposerControls()
    }

    private func refreshComposerControls() async {
        let authenticatedIDs = Set(
            (providerModel?.providers ?? [])
                .filter(\.isAuthenticated)
                .map(\.id))
        await composerControls?.refresh(authenticatedProviderIDs: authenticatedIDs)
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

    private func clearActiveSession() {
        composerControls?.detachActiveSession()
        activeSession = nil
    }

    private func makeSessionController(
        processManager: SessionProcessManager,
        intendedSessionPath: String? = nil
    ) -> SessionController {
        let controller = SessionController(
            processManager: processManager,
            activityRegistry: sessionActivityRegistry)
        managedSessions[controller.id] = controller
        if let intendedSessionPath {
            managedSessionPaths[intendedSessionPath] = controller.id
        }
        return controller
    }

    private func managedController(for sessionPath: String) -> SessionController? {
        if let controllerID = managedSessionPaths[sessionPath] {
            if let controller = managedSessions[controllerID] { return controller }
            managedSessionPaths.removeValue(forKey: sessionPath)
        }
        // A controller learns its path partway through its own open, so the index still
        // lags it. Reuse it from that moment rather than opening a second controller
        // over the same child.
        guard let controller = managedSessions.values
            .first(where: { $0.sessionPath == sessionPath })
        else { return nil }
        managedSessionPaths[sessionPath] = controller.id
        return controller
    }

    private func indexManagedSessionPath(for controller: SessionController) {
        guard managedSessions[controller.id] === controller,
              let sessionPath = controller.sessionPath
        else { return }
        managedSessionPaths[sessionPath] = controller.id
    }

    private func removeManagedSession(_ controller: SessionController) {
        controller.stopActivityTracking()
        managedSessions.removeValue(forKey: controller.id)
        let paths = managedSessionPaths.compactMap { entry in
            entry.value == controller.id ? entry.key : nil
        }
        for path in paths {
            managedSessionPaths.removeValue(forKey: path)
        }
    }

    private func discardManagedSessions() {
        composerControls?.detachActiveSession()
        for controller in managedSessions.values {
            controller.stopActivityTracking()
        }
        managedSessions.removeAll()
        managedSessionPaths.removeAll()
        activeSession = nil
    }

    private func runStartupAttempt(id: UUID, stages: Set<StartupStageID>) async {
        let timing = dependencies.startupTiming
        let minimumVisibility = Task {
            try await timing.sleep(timing.minimumVisibility)
        }
        do {
            let preparation = try await withWatchdog(attemptID: id) {
                try await self.prepareStartup(
                    attemptID: id,
                    stages: stages)
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
        stages: Set<StartupStageID>
    ) async throws -> StartupPreparation {
        if stages.contains(.runtime) {
            let hasRuntime = try await prepareRuntime(attemptID: attemptID)
            if !hasRuntime { return .missingOmp }
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

    private func prepareRuntime(attemptID: UUID) async throws -> Bool {
        startupState.markLoading(.runtime, attemptID: attemptID)
        let location = try await dependencies.ompLocator.locate(preferredURL: nil)
        try checkStartupAttempt(attemptID)
        applySetupDiagnosis(location)

        guard let located = location.installation else {
            await stopProviderUsage()
            let oldProvider = providerModel
            let oldComposerControls = composerControls
            let oldManager = processManager
            discardManagedSessions()
            await oldProvider?.shutdown()
            await oldComposerControls?.shutdown()
            await oldManager?.closeAll()
            try checkStartupAttempt(attemptID)
            await stopProcessWatchers()
            try checkStartupAttempt(attemptID)
            installation = nil
            processManager = nil
            settingsModel = nil
            providerModel = nil
            composerControls = nil
            providerUsages = []
            gateRoute()
            return false
        }

        let isSameExecutable = installation?.executableURL.standardizedFileURL
            == located.executableURL.standardizedFileURL
        let manager: SessionProcessManager
        let settings: SettingsViewModel
        let provider: ProviderManagementViewModel
        let controls: ComposerControlsModel

        if isSameExecutable {
            manager = processManager
                ?? dependencies.makeProcessManager(located.executableURL.path)
            settings = settingsModel
                ?? dependencies.makeSettingsModel(located.executableURL)
            provider = providerModel
                ?? dependencies.makeProviderModel(located.executableURL)
            controls = composerControls
                ?? dependencies.makeComposerControls(located.executableURL)
            try checkStartupAttempt(attemptID)
        } else {
            await stopProviderUsage()
            let oldProvider = providerModel
            let oldComposerControls = composerControls
            let oldManager = processManager
            discardManagedSessions()
            await oldProvider?.shutdown()
            await oldComposerControls?.shutdown()
            await oldManager?.closeAll()
            try checkStartupAttempt(attemptID)
            manager = dependencies.makeProcessManager(located.executableURL.path)
            settings = dependencies.makeSettingsModel(located.executableURL)
            provider = dependencies.makeProviderModel(located.executableURL)
            controls = dependencies.makeComposerControls(located.executableURL)
        }

        try checkStartupAttempt(attemptID)
        installation = located
        processManager = manager
        settingsModel = settings
        providerModel = provider
        composerControls = controls
        gateRoute()
        await restartProcessWatchers(for: manager)
        try checkStartupAttempt(attemptID)
        await stopProviderUsage()
        try checkStartupAttempt(attemptID)
        startProviderUsage(for: provider)
        await provider.loadProviders()
        try checkStartupAttempt(attemptID)
        guard providerModel === provider,
              composerControls === controls
        else { throw CancellationError() }
        await refreshComposerControls()
        try checkStartupAttempt(attemptID)
        guard composerControls === controls else { throw CancellationError() }
        gateRoute()
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
        // Startup assigns `selectedProjectURL` in this stage, after the runtime
        // stage already routed. Without re-gating, every returning user would
        // be shown the project step.
        gateRoute()
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
        let controls = composerControls
        providerModel = nil
        composerControls = nil
        providerUsages = []
        let usage = providerUsageOperation
        providerUsageOperation = nil
        usage?.task.cancel()
        await provider?.shutdown()
        await controls?.shutdown()
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
        let oldComposerControls = composerControls
        let oldManager = processManager
        discardManagedSessions()
        await oldProvider?.shutdown()
        guard isCurrentLifecycle(generation) else { return false }
        await oldComposerControls?.shutdown()
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
            composerControls = nil
            providerUsages = []
            gateRoute()
            return true
        }

        let manager = dependencies.makeProcessManager(located.executableURL.path)
        let settings = dependencies.makeSettingsModel(located.executableURL)
        let provider = dependencies.makeProviderModel(located.executableURL)
        let controls = dependencies.makeComposerControls(located.executableURL)
        guard isCurrentLifecycle(generation) else {
            await provider.shutdown()
            await controls.shutdown()
            await manager.closeAll()
            return false
        }
        installation = located
        processManager = manager
        settingsModel = settings
        providerModel = provider
        composerControls = controls
        providerUsages = []
        gateRoute()
        await restartProcessWatchers(for: manager)
        guard isCurrentLifecycle(generation),
              processManager === manager,
              providerModel === provider,
              composerControls === controls
        else { return false }
        startProviderUsage(for: provider)
        await provider.loadProviders()
        guard isCurrentLifecycle(generation),
              processManager === manager,
              providerModel === provider,
              composerControls === controls
        else { return false }
        await refreshComposerControls()
        guard isCurrentLifecycle(generation),
              composerControls === controls
        else { return false }
        gateRoute()
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
        let controls = composerControls
            ?? dependencies.makeComposerControls(installation.executableURL)
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
        if composerControls == nil {
            guard isCurrentFallback(
                id: id,
                attemptID: attemptID,
                generation: generation,
                lifecycleGeneration: lifecycleGeneration)
            else {
                await controls.shutdown()
                return
            }
            composerControls = controls
        }
        await provider.loadProviders()
        guard isCurrentFallback(
            id: id,
            attemptID: attemptID,
            generation: generation,
            lifecycleGeneration: lifecycleGeneration),
              providerModel === provider
        else { return }
        await refreshComposerControls()
        guard isCurrentFallback(
            id: id,
            attemptID: attemptID,
            generation: generation,
            lifecycleGeneration: lifecycleGeneration),
              composerControls === controls
        else { return }
        gateRoute()
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
            self.providerUsages = provider.dockProviders
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
                        processManager: processManager)
                else { continue }
                guard let controller = self.managedController(for: exit.sessionPath) else { continue }
                controller.handleUnexpectedExit(
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
