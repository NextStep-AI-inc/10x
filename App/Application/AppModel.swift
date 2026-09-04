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

    private enum SessionRenameError: Error {
        case runtimeUnavailable
    }

    private enum StartupPreparation: Sendable {
        case ready
        case missingOmp
    }

    var route: AppRoute = .onboarding(.installOmp)
    var installation: OmpInstallation?
    var selectedProjectURL: URL?
    var newSessionDraft = ""
    var newSessionAttachments: [ComposerAttachment] = []
    private(set) var newSessionFocusRequest = 0
    /// Set when OMP is installed but would not run, so setup can say that
    /// instead of reporting it as missing.
    var unrunnableOmpURL: URL?
    var sessions: [SessionMetadata] = []
    var archivedSessions: [SessionMetadata] = []
    var pendingDeletion: SessionDeletionRequest?
    var pendingRename: SessionRenameRequest?
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
    private(set) var composerCommands: ComposerCommandModel?
    private(set) var startupState = StartupState()
    let sessionActivityRegistry: SessionActivityRegistry
    /// Every managed session's live `ProviderAccountChannel`, keyed by
    /// session id — see `SessionController.attachAccountChannel` (the sole
    /// writer) and `ProviderAccountTieredRoutingBackend`
    /// (`App/Providers/ProviderAccountExtensionBackend.swift`), which reads
    /// it as `sessionActivityRegistry`'s installed `routingBackend` (see
    /// `init`). Owned here (rather than by `AppDependencies`, unlike
    /// `sessionActivityRegistry`) because it needs no factory or
    /// test-double seam of its own: it is a plain, empty-at-construction
    /// registry with no external dependencies, so every `AppModel` gets its
    /// own real one.
    let accountChannelRegistry = ProviderAccountChannelRegistry()

    var providerActivityCounts: [String: Int] {
        sessionActivityRegistry.activeCounts
    }

    /// Removed on main by `9406c7b` as unused once the constrained wheels moved
    /// into the composer footer and stopped greying. The account stack reads it
    /// again: a provider's wheels grey together while the session in front of
    /// the user is generating, which is what tells you the usage you are
    /// looking at is the account currently doing the work.
    var isForegroundSessionGenerating: Bool {
        guard case .session = route else { return false }
        return activeSession?.runtimeState == .streaming
    }

    var menuState: AppMenuState {
        AppMenuState(
            route: route,
            sessions: sessions,
            activeSessionPath: activeSession?.sessionPath,
            runtimeState: activeSession?.runtimeState,
            isSessionMutationInFlight: isSessionMutationInFlight)
    }

    var activeSessionIdentityToken: UUID? {
        activeSession?.id
    }

    var accountGeneratingCounts: [ProviderAccountKey: Int] {
        sessionActivityRegistry.generatingCounts
    }

    var pendingRemovalAccounts: Set<ProviderAccountKey> {
        sessionActivityRegistry.pendingRemovalAccounts
    }

    func accountScopeSatisfaction(
        openSessionID: UUID?
    ) -> [ProviderAccountKey: ProviderAccountScopeSatisfaction] {
        guard let providerModel else { return [:] }
        return providerModel.dockProviders.reduce(into: [:]) { satisfaction, provider in
            guard provider.capability == .accountRouting else { return }
            for account in provider.accounts {
                guard let accountRef = account.accountRef else { continue }
                let key = ProviderAccountKey(providerID: provider.id, accountRef: accountRef)
                satisfaction[key] = sessionActivityRegistry.scopeSatisfaction(
                    providerID: provider.id,
                    accountRef: accountRef,
                    openSessionID: openSessionID)
            }
        }
    }

    func accountScopeAvailability(
        openSessionID: UUID?
    ) -> [String: ProviderAccountScopeAvailability] {
        guard let providerModel else { return [:] }
        return providerModel.dockProviders.reduce(into: [:]) { availability, provider in
            guard provider.capability == .accountRouting else { return }
            availability[provider.id] = sessionActivityRegistry.scopeAvailability(
                providerID: provider.id,
                openSessionID: openSessionID)
        }
    }

    func useProviderAccount(
        _ accountRef: String,
        scope: ProviderAccountScope,
        openSessionID: UUID?
    ) async {
        guard let providerID = providerID(forAccountRef: accountRef) else { return }
        await sessionActivityRegistry.useAccount(
            accountRef,
            providerID: providerID,
            scope: scope,
            openSessionID: openSessionID)
    }

    func manageProviderAccounts(providerID: String) {
        guard !isSessionMutationInFlight else { return }
        providerModel?.focusConnections(providerID: providerID)
        route = .providers(.connections)
    }

    private func providerID(forAccountRef accountRef: String) -> String? {
        providerModel?.dockProviders.first { provider in
            provider.capability == .accountRouting
                && provider.accounts.contains { $0.accountRef == accountRef }
        }?.id
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
    @ObservationIgnored private var composerCommandCatalogIdentity: ObjectIdentifier?
    @ObservationIgnored private(set) var fallbackGeneration = 0
    @ObservationIgnored private(set) var lifecycleGeneration = 0
    @ObservationIgnored private(set) var isShuttingDown = false
    @ObservationIgnored private var workspaceRuntimeReplacementCount = 0
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var hasStartedWarmRetention = false
    @ObservationIgnored private var managedSessions: [UUID: SessionController] = [:]
    @ObservationIgnored private var managedSessionPaths: [String: UUID] = [:]
    @ObservationIgnored private var pendingUnexpectedExits: [
        String: SessionProcessManager.UnexpectedExit
    ] = [:]
    @ObservationIgnored private lazy var updateChecker: any UpdateChecking =
        dependencies.makeUpdateChecker { [weak self] in
            await self?.shutdown()
        }
    @ObservationIgnored private var menuUpdateCheckTask: Task<Void, Never>?
    @ObservationIgnored private var shutdownOperation: Task<Void, Never>?

    var updateState: UpdateState { updateChecker.state }

    init(
        dependencies: AppDependencies = .live,
        ideRegistry: IDERegistry = .init(),
        preferenceDefaults: UserDefaults = .standard,
        fileOpenService: FileOpenService = .live
    ) {
        self.dependencies = dependencies
        sessionActivityRegistry = dependencies.makeProviderAccountCoordinator()
        self.ideRegistry = ideRegistry
        idePreferenceStore = IDEPreferenceStore(defaults: preferenceDefaults, registry: ideRegistry)
        self.fileOpenService = fileOpenService
        startMemoryPressureMonitoring()
        // Installed here, after every stored property has a value (`self`
        // cannot be captured in a closure any earlier), rather than inside
        // `AppDependencies`'s coordinator factory: both arguments close
        // over session-level state (`accountChannelRegistry`,
        // `managedSessions`) that exists only on `AppModel`, never on the
        // dependency-injection composition root. See
        // `ProviderAccountCoordinator.install`'s doc comment for the full
        // reasoning.
        sessionActivityRegistry.install(
            routingBackend: ProviderAccountTieredRoutingBackend(registry: accountChannelRegistry),
            restartSession: { [weak self] sessionID in
                guard let self, let controller = self.managedSessions[sessionID] else { return false }
                await controller.restart()
                // `restart()`'s only failure signal is landing in
                // `.failed` (its `fail(_:function:"restart",...)` path).
                // Its early-return guard (missing `projectURL`/`sessionPath`)
                // leaves `runtimeState` untouched instead, which would read
                // as success here — unreachable in practice, because the
                // coordinator only ever calls this after
                // `ProviderAccountPinBackend.route` already resolved this
                // same session's file via `sessionFileForID`, which
                // requires `sessionPath` to already be non-nil.
                if case .failed = controller.runtimeState { return false }
                return true
            })
    }

    deinit {
        memoryPressureSource?.cancel()
        sessionChangeTask?.cancel()
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

    func checkForUpdatesFromMenu() {
        // `isPresentingUpdate` is false while a check is still running, so it alone does
        // not stop a second check from starting on top of an in-flight one. The menu item
        // is disabled until handoff, which keeps a launch check safe, but a user can click
        // twice in the workspace. One check at a time.
        guard !isShuttingDown,
              !updateState.isPresentingUpdate,
              updateState.phase != .checking
        else { return }
        beginMenuUpdateCheck()
    }

    func acceptUpdate() { updateChecker.accept() }

    func dismissUpdate() { updateChecker.dismiss() }

    func retryUpdate() {
        updateChecker.dismiss()
        beginMenuUpdateCheck()
    }

    /// Starts a user-initiated check and tracks its deadline watchdog, cancelling
    /// whatever watchdog is already running first. The cancel-first step matters: without
    /// it, a stale watchdog from an earlier check could still be asleep when a later
    /// check (a re-click, or `retryUpdate` from a visible failure) begins, wake at its
    /// own deadline, see `state.phase` still `.checking` (now for the *newer* check), and
    /// incorrectly fail it. Only one watchdog may be armed at a time, and it must always
    /// be the one watching the most recent check. Both `checkForUpdatesFromMenu` and
    /// `retryUpdate` route through this rather than calling `UpdateChecking.check(...)`
    /// directly, so a retry from a stalled-and-failed state gets its own deadline too —
    /// otherwise retrying against a still-broken updater would stall silently again.
    private func beginMenuUpdateCheck() {
        menuUpdateCheckTask?.cancel()
        let timing = dependencies.startupTiming
        menuUpdateCheckTask = updateChecker.checkFromMenu(
            deadline: timing.menuUpdateCheckDeadline,
            sleep: timing.sleep)
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
        recordProjectSelection(url)
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
        recordProjectSelection(url)
        scheduleComposerControlsRefresh()
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
        newSessionFocusRequest &+= 1
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
        activeSession?.focusSearchResult(TranscriptSearchRequest(entryID: result.entryID, query: result.query))
    }

    func openPreviousSession() {
        guard let session = menuState.previousSession else { return }
        openSession(session)
    }

    func openNextSession() {
        guard let session = menuState.nextSession else { return }
        openSession(session)
    }

    var railSessions: [SessionMetadata] {
        var result = sessions
        var paths = Set(result.map(\.path))
        var controllers = Array(managedSessions.values)
        if let activeSession, !controllers.contains(where: { $0 === activeSession }) {
            controllers.append(activeSession)
        }
        for controller in controllers {
            let path = controller.sessionPath ?? "new:\(controller.id.uuidString)"
            guard paths.insert(path).inserted, let projectURL = controller.projectURL else { continue }
            let created = controller.createdAt
            result.append(SessionMetadata(path: path, sessionId: controller.id.uuidString,
                cwd: projectURL.path, title: controller.title, created: created, modified: created,
                sizeBytes: 0, status: .pending))
        }
        return result
    }

    func liveController(for sessionPath: String) -> SessionController? {
        if let controller = managedController(for: sessionPath) { return controller }
        let controllers = Array(managedSessions.values) + [activeSession].compactMap { $0 }
        return controllers.first { "new:\($0.id.uuidString)" == sessionPath }
    }

    func openSession(_ metadata: SessionMetadata) {
        guard !isSessionMutationInFlight else { return }
        if !metadata.cwd.isEmpty {
            selectedProjectURL = URL(filePath: metadata.cwd, directoryHint: .isDirectory)
                .standardizedFileURL
        }
        guard let processManager else { return }
        if let controller = liveController(for: metadata.path) {
            detachComposerSources()
            activeSession = controller
            route = .session(metadata.path)
            attachComposerSources(to: controller)
            return
        }
        guard sessionActivityRegistry.canCreateManagedSession else { return }
        let controller = makeSessionController(
            processManager: processManager,
            intendedSessionPath: metadata.path)
        activeSession = controller
        route = .session(metadata.path)
        detachComposerSources()
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
            self.attachComposerSources(to: controller)
        }
    }

    func reviewFailedPrompt(_ controller: SessionController) {
        guard controller.sessionPath == nil else { return }
        if !controller.draft.isEmpty {
            newSessionDraft = [newSessionDraft, controller.draft].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        newSessionAttachments.append(contentsOf: controller.attachments)
        openNewSession()
    }

    func startNewSession(prompt: String, attachments: [ComposerAttachment] = []) {
        guard !isSessionMutationInFlight else { return }
        guard let processManager, let selectedProjectURL else { return }
        guard sessionActivityRegistry.canCreateManagedSession else { return }
        let primarySnapshot = sessionActivityRegistry.newSessionPrimarySnapshot()
        let controller = makeSessionController(processManager: processManager)
        controller.prepareInitialSubmission(text: prompt, attachments: attachments, projectURL: selectedProjectURL)
        newSessionDraft = ""
        newSessionAttachments = []
        detachComposerSources()
        // omp does not name the session until the child is up, so the route
        // carries a placeholder until `openNew` reports the real path.
        let placeholderRoute = AppRoute.session("new:\(controller.id.uuidString)")
        route = placeholderRoute
        let selection = composerControls?.spawnSelection
        activeSession = controller
        Task { [weak self, controller, selectedProjectURL, selection, primarySnapshot] in
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
                controller.markInitialSubmissionFailed()
                self.removeManagedSession(controller)
                return
            }
            self.indexManagedSessionPath(for: controller)
            await self.sessionActivityRegistry.prepareForFirstPrompt(
                sessionID: controller.id,
                primarySnapshot: primarySnapshot)
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
                    self.attachComposerSources(to: controller)
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
        startupState.enterRecovery(attemptID: attemptID,
            reason: "Paused to free memory. Retry when memory is available or continue without preloaded workspaces.")
    }

    /// Runs once and is re-entrant: a second caller awaits the *completion* of the
    /// shutdown already in flight rather than returning immediately. Both Sparkle's
    /// install path (`prepareForInstall`) and `AppTerminationDelegate` call this, and a
    /// second caller returning early let the app quit while OMP children were still
    /// being reaped — the delegate would set `isShutdownComplete` and reply
    /// `.terminateNow` off a shutdown that had barely started.
    func shutdown() async {
        if let shutdownOperation {
            await shutdownOperation.value
            return
        }
        // Set before the task is created, not inside it, so every guard that reads
        // `isShuttingDown` sees it the moment this function is entered.
        isShuttingDown = true
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performShutdown()
        }
        shutdownOperation = operation
        await operation.value
    }

    private func performShutdown() async {
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
        let menuUpdateCheck = menuUpdateCheckTask
        menuUpdateCheckTask = nil
        menuUpdateCheck?.cancel()

        let provider = providerModel
        let controls = composerControls
        let manager = processManager
        discardManagedSessions()
        discardComposerCommands()
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
        await menuUpdateCheck?.value
    }

    func requestDeleteSession(_ metadata: SessionMetadata) {
        pendingDeletion = .session(metadata)
    }

    func requestRenameSession(_ metadata: SessionMetadata) {
        guard !isSessionMutationInFlight else { return }
        pendingRename = SessionRenameRequest(metadata: metadata)
    }

    func requestRenameCurrentSession() {
        guard !isSessionMutationInFlight,
              let controller = activeSession,
              let path = controller.sessionPath
        else { return }
        pendingRename = SessionRenameRequest(
            path: path,
            cwd: controller.projectURL?.path ?? selectedProjectURL?.path ?? "",
            title: controller.title)
    }

    func updateRenameDraft(_ draft: String) {
        guard var request = pendingRename, !isSessionMutationInFlight else { return }
        request.draft = draft
        request.errorMessage = nil
        pendingRename = request
    }

    func cancelRename() {
        guard !isSessionMutationInFlight else { return }
        pendingRename = nil
    }

    func confirmRename() async {
        guard var request = pendingRename else { return }
        guard let title = request.normalizedTitle else {
            request.errorMessage = "Enter a session name."
            pendingRename = request
            return
        }
        guard beginSessionMutation() else { return }
        defer { endSessionMutation() }

        request.errorMessage = nil
        pendingRename = request
        do {
            if let controller = managedController(for: request.path) {
                try await controller.rename(to: title)
            } else {
                try await renameColdSession(request, to: title)
            }
            await reloadSessions()
            await reloadArchivedSessions()
            guard pendingRename?.id == request.id else { return }
            pendingRename = nil
        } catch {
            guard var current = pendingRename, current.id == request.id else { return }
            current.errorMessage = "Could not rename this session."
            pendingRename = current
        }
    }

    private func renameColdSession(
        _ request: SessionRenameRequest,
        to title: String
    ) async throws {
        guard let processManager else { throw SessionRenameError.runtimeUnavailable }
        if let handle = await processManager.handle(for: request.path) {
            _ = try await handle.client.send(.setSessionName(title))
            return
        }

        let handle = try await processManager.open(sessionPath: request.path, cwd: request.cwd)
        do {
            _ = try await handle.client.send(.setSessionName(title))
            await processManager.close(sessionPath: request.path)
        } catch {
            await processManager.close(sessionPath: request.path)
            throw error
        }
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
        await archiveSession(path: metadata.path, subject: sessionDisplayName(metadata))
    }

    func archiveCurrentSession() async {
        guard let path = menuState.currentSessionPath else { return }
        let subject = sessions.first(where: { $0.path == path }).map(sessionDisplayName)
            ?? activeSession?.title
            ?? "Untitled session"
        await archiveSession(path: path, subject: subject)
    }

    private func archiveSession(path: String, subject: String) async {
        guard beginSessionMutation() else { return }
        defer { endSessionMutation() }
        await mutateActive(
            paths: [path],
            action: "archive",
            subject: subject) {
                await dependencies.sessionLibrary.archive(paths: [path])
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
        detachComposerSources()
        scheduleComposerControlsRefresh()
    }

    private func scheduleComposerControlsRefresh() {
        composerControlsRefreshGeneration &+= 1
        let generation = composerControlsRefreshGeneration
        Task { await refreshComposerControlsIfCurrent(generation: generation) }
    }

    private func recordProjectSelection(_ url: URL) {
        selectProject(url, recordInRecentProjects: true)
    }

    private func selectProject(_ url: URL, recordInRecentProjects: Bool) {
        let project = url.standardizedFileURL
        selectedProjectURL = project
        guard recordInRecentProjects else { return }
        dependencies.recentProjectStore.recordSelection(project)
    }

    private func refreshComposerControlsForCurrentSelection() async {
        composerControlsRefreshGeneration &+= 1
        let generation = composerControlsRefreshGeneration
        await refreshComposerControlsIfCurrent(generation: generation)
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
        await composerControls?.refresh(
            authenticatedProviderIDs: authenticatedIDs,
            projectURL: selectedProjectURL)
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
        detachComposerSources()
        activeSession = nil
    }

    private func makeSessionController(
        processManager: SessionProcessManager,
        intendedSessionPath: String? = nil
    ) -> SessionController {
        let controller = SessionController(
            processManager: processManager,
            activityRegistry: sessionActivityRegistry,
            accountChannelRegistry: accountChannelRegistry,
            titleGenerator: installation.flatMap {
                dependencies.makeSessionTitleGenerator($0.executableURL)
            })
        managedSessions[controller.id] = controller
        if let intendedSessionPath {
            managedSessionPaths[intendedSessionPath] = controller.id
        }
        return controller
    }

    // Not private: the navigation tests wait on the reuse registry rather than on
    // activeSession.sessionPath, which a controller sets partway through its open.
    func managedController(for sessionPath: String) -> SessionController? {
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
        if let exit = pendingUnexpectedExits.removeValue(forKey: sessionPath) {
            handleUnexpectedExit(exit, controller: controller)
        }
    }

    private func receiveUnexpectedExit(_ exit: SessionProcessManager.UnexpectedExit) {
        if let controller = managedController(for: exit.sessionPath)
            ?? managedSessions.values.first(where: { $0.sessionPath == exit.sessionPath })
        {
            managedSessionPaths[exit.sessionPath] = controller.id
            handleUnexpectedExit(exit, controller: controller)
        } else {
            pendingUnexpectedExits[exit.sessionPath] = exit
        }
    }

    private func handleUnexpectedExit(
        _ exit: SessionProcessManager.UnexpectedExit,
        controller: SessionController
    ) {
        controller.handleUnexpectedExit(code: exit.code, stderrTail: exit.stderrTail)
        sessionActivityRegistry.unregister(sessionID: controller.id)
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
        detachComposerSources()
        for controller in managedSessions.values {
            controller.stopActivityTracking()
        }
        managedSessions.removeAll()
        managedSessionPaths.removeAll()
        pendingUnexpectedExits.removeAll()
        activeSession = nil
    }

    private func attachComposerSources(to controller: SessionController) {
        composerControls?.attachActiveSession(controller)
        composerCommands?.attachActiveSession(controller)
    }

    private func detachComposerSources() {
        composerControls?.detachActiveSession()
        composerCommands?.detachActiveSession()
    }

    private func bindComposerCommands(to controls: ComposerControlsModel) {
        let identity = ObjectIdentifier(controls.catalog)
        guard composerCommandCatalogIdentity != identity || composerCommands == nil else {
            return
        }
        composerCommands?.stopObservingCatalog()
        composerCommandCatalogIdentity = identity
        composerCommands = ComposerCommandModel(
            catalog: controls.catalog,
            controls: controls,
            onStartNewSession: { [weak self] prompt, attachments in
                self?.startNewSession(prompt: prompt, attachments: attachments)
            })
    }

    private func discardComposerCommands() {
        composerCommands?.stopObservingCatalog()
        composerCommands = nil
        composerCommandCatalogIdentity = nil
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
                await updateChecker.state.waitWhilePresenting()
                // The gate also opens on cancellation, which is how an accepted update
                // gets out of here: `shutdown()` cancels this task and then awaits it
                // from inside Sparkle's install callback. Handing off from a cancelled
                // attempt would flash a workspace window open over an install that is
                // about to replace the app. Re-check both, because `isShuttingDown` is
                // set before this task is cancelled and either one can arrive first.
                guard !isShuttingDown, !Task.isCancelled else { return }
                startupState.requestHandoff(attemptID: id)
            }
        } catch {
            minimumVisibility.cancel()
            _ = await minimumVisibility.result
            guard !Task.isCancelled,
                  startupState.attemptID == id,
                  startupState.phase == .preparing
            else { return }
            let reason: String
            if case StartupAttemptError.timeout = error {
                reason = "Startup exceeded its time limit. Retry the unfinished step or continue with what is ready."
            } else {
                reason = "The step could not finish (\(String(describing: type(of: error)))). Retry or continue with what is ready."
            }
            startupState.enterRecovery(attemptID: id, reason: reason)
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
            if !hasRuntime {
                startupState.markReady(.updates, attemptID: attemptID)
                return .missingOmp
            }
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
            if stages.contains(.updates) {
                group.addTask { await self.prepareUpdates(attemptID: attemptID) }
            }
            try await group.waitForAll()
        }
        try checkStartupAttempt(attemptID)
        return .ready
    }

    /// Advisory. Deliberately non-throwing and deliberately incapable of marking the row
    /// stopped, so a network failure or a slow feed can never put the splash into
    /// recovery or extend the launch beyond the deadline.
    private func prepareUpdates(attemptID: UUID) async {
        startupState.markLoading(.updates, attemptID: attemptID)
        await updateChecker.checkAtLaunch(
            deadline: dependencies.startupTiming.updateCheckDeadline,
            sleep: dependencies.startupTiming.sleep)
        startupState.resolveAdvisoryCheck(attemptID: attemptID)
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
            discardComposerCommands()
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
            composerCommands = nil
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
            discardComposerCommands()
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
        bindComposerCommands(to: controls)
        gateRoute()
        await restartProcessWatchers(for: manager)
        try checkStartupAttempt(attemptID)
        await stopProviderUsage()
        try checkStartupAttempt(attemptID)
        configureProviderModel(provider)
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
            await startSessionChangeWatching()
            startupState.markReady(.sessions, attemptID: attemptID)
        }

        guard stages.contains(.recentProjects) else { return }
        try checkStartupAttempt(attemptID)
        startupState.markLoading(.recentProjects, attemptID: attemptID)
        let projects = dependencies.recentProjectStore.rankedProjects(sessions: sessions)
        if selectedProjectURL == nil, let project = projects.first {
            selectProject(project, recordInRecentProjects: false)
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
        await refreshComposerControlsForCurrentSelection()
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
        discardComposerCommands()
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
        discardComposerCommands()
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
            composerCommands = nil
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
        bindComposerCommands(to: controls)
        providerUsages = []
        gateRoute()
        await restartProcessWatchers(for: manager)
        guard isCurrentLifecycle(generation),
              processManager === manager,
              providerModel === provider,
              composerControls === controls
        else { return false }
        configureProviderModel(provider)
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
                await self.startSessionChangeWatching()
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
            configureProviderModel(provider)
        }
        if composerControls == nil {
            guard isCurrentFallback(
                id: id,
                attemptID: attemptID,
                generation: generation,
                lifecycleGeneration: lifecycleGeneration)
            else {
                discardComposerCommands()
                await controls.shutdown()
                return
            }
            composerControls = controls
        }
        bindComposerCommands(to: controls)
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

    private func startSessionChangeWatching() async {
        guard sessionChangeTask == nil, !isShuttingDown else { return }
        let library = dependencies.sessionLibrary
        await library.startWatching()
        guard sessionChangeTask == nil, !isShuttingDown else { return }
        sessionChangeGeneration &+= 1
        let generation = sessionChangeGeneration
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

    /// Runs once for every freshly (re)created `providerModel`, in place of
    /// calling `startProviderUsage` directly: installs how account removal
    /// reaches the extension and how tier detection learns whether one is
    /// even listening, then starts the usage load. Both installs close over
    /// `accountChannelRegistry`, which — like `sessionActivityRegistry`'s
    /// routing backend (see `init`'s `sessionActivityRegistry.install` call
    /// and its doc comment) — exists only here, never in
    /// `AppDependencies.makeProviderModel`'s zero-argument factory, so
    /// composing either can't happen at construction time. Unlike the
    /// coordinator, `providerModel` is not a single construction-time
    /// singleton — `replaceWorkspaceRuntime` and `loadProviderFallback` both
    /// rebuild or reuse it across the app's lifetime — so this runs at
    /// every site that assigns a new one, not once from `init`.
    ///
    /// The removal transport tries any currently attached session channel
    /// (`ProviderAccountChannelRegistry.anyChannel()`): removal reaches
    /// `ctx.modelRegistry.authStorage`, which every session's extension
    /// instance shares, so which session's channel carries the command does
    /// not matter (see `anyChannel()`'s doc comment). No channel attached —
    /// no live session, or the stock tier, which has no removal path at all
    /// (`ProviderAccountTier.supportsRemoval`) — throws `.unavailable`
    /// rather than inventing one.
    ///
    /// **Reconciling two different lifetimes (task-10b fix round 1,
    /// "Finding 1").** `accountChannelRegistry`'s entries are session-scoped
    /// — attached when a session's frames start flowing, detached when its
    /// pipeline stops (`SessionController.attachAccountChannel`/
    /// `stopEventPipeline`) — while tier detection runs from
    /// `ProviderManagementViewModel.refreshAccountUsage`, a provider
    /// refresh with no session in the picture at all. This install reuses
    /// the exact same reconciliation the removal transport above already
    /// made: `anyChannel()` again, because `hello`'s answer — like
    /// `removeAccount`'s effect — is not session data, it's a fact about
    /// the app's one bundled extension build, so any live channel gives the
    /// same answer any other would. Before any session exists,
    /// `anyChannel()` returns `nil`, the closure returns `nil`, and
    /// `resolveExtensionHello()` reports no hello available — which
    /// `ProviderAccountTier.detect` already treats exactly like a
    /// channel that answered with the wrong contract version: fail closed
    /// to `.stockOMP` (or `.providerOnly`, if the snapshot has no
    /// per-account identity at all yet either). So "the tier before any
    /// session exists" is never `.extensionBacked` — it's whatever the
    /// usage snapshot alone supports, same as stock OMP with the extension
    /// absent entirely, until a session attaches a channel and a later
    /// refresh's probe succeeds.
    private func configureProviderModel(_ provider: ProviderManagementViewModel) {
        provider.installTierHelloProvider { [weak self] in
            guard let self, let channel = self.accountChannelRegistry.anyChannel() else { return nil }
            return await ProviderAccountExtensionBackend(channel: channel).hello()
        }
        provider.installAccountRemovalTransport { [weak self] providerID, accountRef in
            guard let self, let channel = self.accountChannelRegistry.anyChannel() else {
                throw ProviderAccountChannelError.unavailable
            }
            return try await ProviderAccountExtensionBackend(channel: channel).removeAccount(
                providerID: providerID, accountRef: accountRef)
        }
        // Task-10b final fix, Finding 2: keeps `provider.accountTier` from
        // going stale in either direction against this same registry — see
        // `ProviderAccountChannelRegistry.onAvailabilityChange`'s doc
        // comment for the two directions, and `ProviderManagementViewModel
        // .redetectAccountTier`'s for why recomputing the tier alone is
        // enough. `[weak provider]` because this closure is retained by
        // `accountChannelRegistry`, which outlives any one `providerModel`
        // across `replaceWorkspaceRuntime`/`loadProviderFallback` rebuilds.
        accountChannelRegistry.onAvailabilityChange = { [weak provider] in
            provider?.redetectAccountTier()
        }
        startProviderUsage(for: provider)
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
                self.receiveUnexpectedExit(exit)
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
        pendingUnexpectedExits.removeAll()
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
        startupState.enterRecovery(attemptID: attemptID,
            reason: "A workspace process exited during startup. Retry it or continue without preloaded workspaces.")
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
