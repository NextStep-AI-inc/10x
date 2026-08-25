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
    private(set) var activeSession: SessionController?
    private(set) var processManager: SessionProcessManager?
    private(set) var settingsModel: SettingsViewModel?

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    @ObservationIgnored private var archivedReloadGeneration = 0

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
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
        selectedProjectURL = url.standardizedFileURL
        activeSession = nil
        route = .newSession
    }

    func openSettings() {
        route = .settings
        Task { await settingsModel?.load() }
    }

    func openNewSession() {
        activeSession = nil
        route = .newSession
    }

    func openArchivedSessions() {
        route = .archivedSessions
        Task { await reloadArchivedSessions() }
    }

    func openSearch() {
        isSearchPresented = true
    }

    func closeSearch() {
        isSearchPresented = false
    }

    func openSearchResult(_ result: SearchResult) {
        guard let metadata = sessions.first(where: { $0.path == result.sessionPath }) else { return }
        closeSearch()
        openSession(metadata)
    }

    func openSession(_ metadata: SessionMetadata) {
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
        invalidateArchivedSessionReloads()
        await finish(
            await dependencies.sessionLibrary.restore(paths: [metadata.path]),
            action: "restore",
            subject: sessionDisplayName(metadata))
    }

    func restoreProject(_ group: ProjectSessionGroup) async {
        invalidateArchivedSessionReloads()
        await finish(
            await dependencies.sessionLibrary.restore(paths: group.sessions.map(\.path)),
            action: "restore",
            subject: "\(group.displayName) sessions")
    }

    func confirmDeletion() async {
        guard let request = pendingDeletion else { return }
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
        guard case .session(let routePath) = route else { return }
        let activePath = activeSession?.sessionPath
        let matchingPath: String? = if let activePath, paths.contains(activePath) {
            activePath
        } else if paths.contains(routePath) {
            routePath
        } else {
            nil
        }
        guard let matchingPath else { return }
        await processManager?.close(sessionPath: matchingPath)
        activeSession = nil
        route = .newSession
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

    private func sessionDisplayName(_ metadata: SessionMetadata) -> String {
        metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
    }

    private func install(preferredURL: URL?) async {
        guard let installation = await dependencies.ompLocator.locate(preferredURL: preferredURL) else {
            exitTask?.cancel()
            self.installation = nil
            processManager = nil
            settingsModel = nil
            route = .setup
            return
        }

        self.installation = installation
        let processManager = SessionProcessManager(executable: installation.executableURL.path)
        self.processManager = processManager
        settingsModel = SettingsViewModel(service: OmpConfigService(
            runner: OmpConfigProcessRunner(executableURL: installation.executableURL)))
        watchUnexpectedExits(from: processManager)
        setupError = nil
        route = .newSession
    }

    private func watchUnexpectedExits(from processManager: SessionProcessManager) {
        exitTask?.cancel()
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
    }
}
