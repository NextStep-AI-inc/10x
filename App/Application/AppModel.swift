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
    var isSearchPresented = false
    private(set) var activeSession: SessionController?
    private(set) var processManager: SessionProcessManager?
    private(set) var settingsModel: SettingsViewModel?
    private(set) var providerModel: ProviderManagementViewModel?

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var exitTask: Task<Void, Never>?

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func bootstrap() async {
        await install(preferredURL: nil)
        await reloadSessions()
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

    func openProviders(_ section: ProviderWorkspaceSection) {
        providerModel?.selectedSection = section
        route = .providers(section)
    }

    func refreshProvidersIfNeeded() async {
        await providerModel?.refreshIfStale()
    }

    func openNewSession() {
        activeSession = nil
        route = .newSession
    }

    func completeProviderSetup() {
        guard providerModel?.hasAuthenticatedProvider == true else { return }
        route = .newSession
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

    private func install(preferredURL: URL?) async {
        let locatedInstallation = await dependencies.ompLocator.locate(preferredURL: preferredURL)
        if let providerModel {
            await providerModel.shutdown()
        }

        guard let installation = locatedInstallation else {
            exitTask?.cancel()
            self.installation = nil
            processManager = nil
            settingsModel = nil
            providerModel = nil
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
        watchUnexpectedExits(from: processManager)
        setupError = nil
        route = .providerSetup
        Task { [weak providerModel] in
            await providerModel?.loadUsage()
        }
        await providerModel.loadProviders()
        guard self.providerModel === providerModel else { return }
        if providerModel.hasAuthenticatedProvider {
            route = .newSession
        }
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
