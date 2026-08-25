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
    var providerUsages: [ProviderUsageProvider] = []
    var isSearchPresented = false
    private(set) var activeSession: SessionController?
    private(set) var processManager: SessionProcessManager?
    private(set) var settingsModel: SettingsViewModel?

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private var exitTask: Task<Void, Never>?
    @ObservationIgnored private var sessionTransitionTask: Task<Void, Never>?
    @ObservationIgnored private var transitioningSession: SessionController?
    @ObservationIgnored private var sessionTransitionGeneration = 0

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
        retireActiveSessionInBackground()
        route = .newSession
    }

    func openSettings() {
        route = .settings
        Task { await settingsModel?.load() }
    }

    func openNewSession() {
        retireActiveSessionInBackground()
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
        guard processManager != nil else { return }
        let prior = beginSessionTransition()
        let generation = sessionTransitionGeneration
        route = .session(metadata.path)
        sessionTransitionTask = Task { [weak self] in
            await prior?.value
            guard let self,
                  self.sessionTransitionGeneration == generation,
                  let processManager = self.processManager
            else { return }
            let controller = SessionController(
                processManager: processManager,
                computerUseRegistry: self.dependencies.computerUseRegistry)
            self.activeSession = controller
            self.transitioningSession = nil
            await controller.openExisting(metadata)
            if self.sessionTransitionGeneration != generation {
                await controller.teardown()
                if self.activeSession === controller { self.activeSession = nil }
            }
        }
    }

    func startNewSession(prompt: String) {
        guard processManager != nil, let selectedProjectURL else { return }
        let prior = beginSessionTransition()
        let generation = sessionTransitionGeneration
        route = .session("new:\(UUID().uuidString)")
        sessionTransitionTask = Task { [weak self] in
            await prior?.value
            guard let self,
                  self.sessionTransitionGeneration == generation,
                  let processManager = self.processManager
            else { return }
            let controller = SessionController(
                processManager: processManager,
                computerUseRegistry: self.dependencies.computerUseRegistry)
            controller.draft = prompt
            self.activeSession = controller
            self.transitioningSession = nil
            await controller.openNew(projectURL: selectedProjectURL)
            await controller.sendPrompt()
            await self.reloadSessions()
            if self.sessionTransitionGeneration != generation {
                await controller.teardown()
                if self.activeSession === controller { self.activeSession = nil }
            }
        }
    }

    func reloadSessions() async {
        sessions = await dependencies.sessionLibrary.listAll()
    }

    private func install(preferredURL: URL?) async {
        await retireActiveSession()
        if let processManager { await processManager.closeAll() }
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
                guard let self, !Task.isCancelled else { continue }
                let owner: SessionController?
                if self.activeSession?.sessionPath == exit.sessionPath {
                    owner = self.activeSession
                } else if self.transitioningSession?.sessionPath == exit.sessionPath {
                    owner = self.transitioningSession
                } else {
                    owner = nil
                }
                guard let owner else { continue }
                await owner.handleUnexpectedExit(
                    code: exit.code,
                    stderrTail: exit.stderrTail)
            }
        }
    }

    private func beginSessionTransition() -> Task<Void, Never>? {
        sessionTransitionGeneration += 1
        let prior = sessionTransitionTask
        let retiring = activeSession
        activeSession = nil
        transitioningSession = retiring
        sessionTransitionTask = Task { [weak self] in
            await prior?.value
            await retiring?.teardown()
            guard let self,
                  self.transitioningSession === retiring
            else { return }
            self.transitioningSession = nil
        }
        return sessionTransitionTask
    }

    private func retireActiveSessionInBackground() {
        _ = beginSessionTransition()
    }

    private func retireActiveSession() async {
        let prior = beginSessionTransition()
        await prior?.value
    }
}
