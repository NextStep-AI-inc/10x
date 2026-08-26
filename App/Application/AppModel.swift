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
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var exitTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var sessionTransitionTask: Task<Void, Never>?
    @ObservationIgnored private var retiringSessions: [ObjectIdentifier: SessionController] = [:]
    @ObservationIgnored private var sessionTransitionGeneration = 0

    init(dependencies: AppDependencies = .live, defaults: UserDefaults = .standard) {
        self.dependencies = dependencies
        self.defaults = defaults
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
            let controller = self.dependencies.makeSessionController(
                processManager,
                self.dependencies.computerUseRegistry,
                ComputerUsePreferenceStore.preference(defaults: self.defaults))
            self.activeSession = controller
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
            let controller = self.dependencies.makeSessionController(
                processManager,
                self.dependencies.computerUseRegistry,
                ComputerUsePreferenceStore.preference(defaults: self.defaults))
            controller.draft = prompt
            self.activeSession = controller
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
        let priorManager = processManager
        await retireActiveSession()
        if let priorManager {
            let safetyPaths = Set<String>(retiringSessions.values.compactMap { controller in
                guard controller.usesProcessManager(priorManager),
                      controller.computerUse.isAwaitingConfirmedProcessExit
                else { return nil }
                return controller.processSessionPath(from: priorManager)
            })
            await priorManager.closeAll(excludingSessionPaths: safetyPaths)
        }
        guard let installation = await dependencies.ompLocator.locate(preferredURL: preferredURL) else {
            self.installation = nil
            processManager = nil
            settingsModel = nil
            route = .setup
            if let priorManager { stopWatchingIfUnused(priorManager) }
            return
        }

        self.installation = installation
        let processManager = dependencies.makeProcessManager(installation.executableURL.path)
        self.processManager = processManager
        settingsModel = SettingsViewModel(
            service: OmpConfigService(runner: OmpConfigProcessRunner(executableURL: installation.executableURL)),
            computerUseSetup: ComputerUseSetupModel(
                omp: DisposableComputerUseOMP(executable: installation.executableURL.path),
                ompVersion: installation.version))
        watchUnexpectedExits(from: processManager)
        setupError = nil
        route = .newSession
        if let priorManager { stopWatchingIfUnused(priorManager) }
    }

    private func watchUnexpectedExits(from processManager: SessionProcessManager) {
        let managerID = ObjectIdentifier(processManager)
        exitTasks[managerID]?.cancel()
        exitTasks[managerID] = Task { [weak self, processManager] in
            for await exit in processManager.unexpectedExits {
                guard let self, !Task.isCancelled else { continue }
                let retiringOwners = self.retiringSessions.filter {
                    $0.value.ownsProcess(from: processManager, generation: exit.generation)
                }
                let activeOwner = self.activeSession?.ownsProcess(
                    from: processManager,
                    generation: exit.generation) == true
                    ? self.activeSession : nil
                var owners = retiringOwners.map(\.value)
                let retiringIDs = Set(retiringOwners.keys)
                if let activeOwner,
                   !retiringIDs.contains(ObjectIdentifier(activeOwner)) {
                    owners.append(activeOwner)
                }
                for owner in owners {
                    await owner.handleUnexpectedExit(
                        code: exit.code,
                        stderrTail: exit.stderrTail)
                    let ownerID = ObjectIdentifier(owner)
                    if self.retiringSessions[ownerID] === owner {
                        self.retiringSessions.removeValue(forKey: ownerID)
                    }
                }
                if self.processManager !== processManager,
                   !self.retiringSessions.values.contains(where: {
                       $0.usesProcessManager(processManager)
                   }) {
                    self.exitTasks.removeValue(forKey: managerID)
                    return
                }
            }
        }
    }

    private func beginSessionTransition() -> Task<Void, Never>? {
        sessionTransitionGeneration += 1
        let prior = sessionTransitionTask
        let retiring = activeSession
        activeSession = nil
        if let retiring {
            retiringSessions[ObjectIdentifier(retiring)] = retiring
        }
        sessionTransitionTask = Task { [weak self] in
            await prior?.value
            await retiring?.teardown()
            guard let self, let retiring else { return }
            if !retiring.computerUse.isAwaitingConfirmedProcessExit {
                self.retiringSessions.removeValue(forKey: ObjectIdentifier(retiring))
            }
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

    private func stopWatchingIfUnused(_ manager: SessionProcessManager) {
        guard processManager !== manager,
              !retiringSessions.values.contains(where: { $0.usesProcessManager(manager) })
        else { return }
        exitTasks.removeValue(forKey: ObjectIdentifier(manager))?.cancel()
    }
}
