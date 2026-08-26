import AppKit
import Foundation
import Observation
import OmpKit

@MainActor
@Observable
final class AppModel {
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
    private(set) var composerControls: ComposerControlsModel?
    let sessionActivityRegistry = SessionActivityRegistry()

    var providerActivityCounts: [String: Int] {
        sessionActivityRegistry.activeCounts
    }

    var isForegroundSessionGenerating: Bool {
        guard case .session = route else { return false }
        return activeSession?.runtimeState == .streaming
    }

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    @ObservationIgnored private var archivedReloadGeneration = 0
    @ObservationIgnored private var composerControlsRefreshGeneration = 0
    @ObservationIgnored private var routeBeforeSettings: AppRoute?
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
    }

    var sessionSearch: any SessionSearching {
        dependencies.sessionSearch
    }

    func bootstrap() async {
        await install(preferredURL: nil)
        await reloadSessions()
        await reloadArchivedSessions()
    }

    func useOmp(at url: URL) async {
        await install(preferredURL: url)
        if installation == nil {
            setupError = OmpExecutableLocator.inspectionErrorDescription(for: url)
        }
    }

    func chooseProject(_ url: URL) {
        guard !isSessionMutationInFlight else { return }
        selectedProjectURL = url.standardizedFileURL
        clearActiveSession()
        detachComposerControlsAndRefresh()
        route = .newSession
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
        case .setup, .providerSetup, .settings:
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
        guard providerModel?.hasAuthenticatedProvider == true else { return }
        route = .newSession
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

    func startNewSession(prompt: String) {
        guard !isSessionMutationInFlight else { return }
        guard let processManager, let selectedProjectURL else { return }
        let controller = makeSessionController(processManager: processManager)
        controller.draft = prompt
        composerControls?.detachActiveSession()
        route = .session("new:\(UUID().uuidString)")
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
            guard controller.sessionPath != nil else {
                self.removeManagedSession(controller)
                return
            }
            self.indexManagedSessionPath(for: controller)
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

    private func install(preferredURL: URL?) async {
        let locatedInstallation = await dependencies.ompLocator.locate(preferredURL: preferredURL)
        if let providerModel {
            await providerModel.shutdown()
        }
        if let composerControls {
            await composerControls.shutdown()
        }
        await discardManagedSessions()

        guard let installation = locatedInstallation else {
            self.installation = nil
            settingsModel = nil
            providerModel = nil
            composerControls = nil
            route = .setup
            return
        }

        self.installation = installation
        let processManager = SessionProcessManager(executable: installation.executableURL.path)
        self.processManager = processManager
        settingsModel = SettingsViewModel(service: OmpConfigService(
            runner: OmpConfigProcessRunner(executableURL: installation.executableURL)))
        let providerModel = dependencies.makeProviderModel(installation.executableURL)
        self.providerModel = providerModel
        let composerControls = dependencies.makeComposerControls(installation.executableURL)
        self.composerControls = composerControls
        watchUnexpectedExits(from: processManager)
        setupError = nil
        route = .providerSetup
        Task { [weak providerModel] in
            await providerModel?.loadUsage()
        }
        await providerModel.loadProviders()
        guard self.providerModel === providerModel else { return }
        await refreshComposerControls()
        if providerModel.hasAuthenticatedProvider {
            route = .newSession
        }
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
        guard let controllerID = managedSessionPaths[sessionPath] else { return nil }
        guard let controller = managedSessions[controllerID] else {
            managedSessionPaths.removeValue(forKey: sessionPath)
            return nil
        }
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

    private func discardManagedSessions() async {
        for controller in managedSessions.values {
            controller.stopActivityTracking()
        }
        managedSessions.removeAll()
        managedSessionPaths.removeAll()
        activeSession = nil
        exitTask?.cancel()
        exitTask = nil
        let previousProcessManager = processManager
        processManager = nil
        await previousProcessManager?.closeAll()
    }

    private func watchUnexpectedExits(from processManager: SessionProcessManager) {
        exitTask?.cancel()
        exitTask = Task { [weak self] in
            for await exit in processManager.unexpectedExits {
                guard let self, !Task.isCancelled else { return }
                guard let controller = managedController(for: exit.sessionPath) else { continue }
                controller.handleUnexpectedExit(
                    code: exit.code,
                    stderrTail: exit.stderrTail)
            }
        }
    }
}
