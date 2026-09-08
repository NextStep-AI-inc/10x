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
    var providerUsages: [ProviderUsageProvider] = []
    var isSearchPresented = false
    private(set) var activeSession: SessionController?
    private(set) var processManager: SessionProcessManager?
    private(set) var settingsModel: SettingsViewModel?
    var activeComputerUse: ComputerUseController? { activeSession?.computerUse }

    /// ponytail: only sessions with a live controller report activity (active +
    /// retiring). Ceiling: a background session that keeps controlling while
    /// closed loses its badge until reopened. Upgrade path: persist claims per
    /// session path in the daemon and query by path.
    var computerUseActiveSessionPaths: Set<String> {
        var paths = Set<String>()
        func collect(from controller: SessionController) {
            if controller.computerUse.isEnabled, let path = controller.sessionPath {
                paths.insert(path)
            }
        }
        if let activeSession { collect(from: activeSession) }
        for retiring in retiringSessions.values { collect(from: retiring) }
        return paths
    }

    let supervision: SupervisionClient

    @ObservationIgnored private let dependencies: AppDependencies
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var exitTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    @ObservationIgnored private var sessionTransitionTask: Task<Void, Never>?
    @ObservationIgnored private var retiringSessions: [ObjectIdentifier: SessionController] = [:]
    @ObservationIgnored private var sessionTransitionGeneration = 0
    @ObservationIgnored private let emergencyShortcut = GlobalEmergencyShortcut()
    @ObservationIgnored private var lifecycleTokens: [NSObjectProtocol] = []

    init(dependencies: AppDependencies = .live, defaults: UserDefaults = .standard) {
        self.dependencies = dependencies
        self.defaults = defaults
        supervision = dependencies.supervisionClient
    }

    func bootstrap() async {
        installComputerUseLifecycleObservers()
        supervision.start()
        supervision.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.activeSession?.computerUse.applySupervision(event)
            }
        }
        updateEmergencyShortcut()
        await install(preferredURL: nil)
        await reloadSessions()
    }

    func updateEmergencyShortcut() {
        emergencyShortcut.update(isActive: supervision.hasAnyActivity) { [weak self] in
            self?.supervision.stopAll()
        }
    }

    func stopActiveComputerUse() async {
        guard let activeComputerUse else { return }
        await activeComputerUse.stopComputerUse()
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
                self.dependencies.supervisionClient)
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
                self.dependencies.supervisionClient)
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
            await priorManager.closeAll()
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
            computerUseSetup: ComputerUseSetupModel())
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
            self.retiringSessions.removeValue(forKey: ObjectIdentifier(retiring))
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

    private func installComputerUseLifecycleObservers() {
        guard lifecycleTokens.isEmpty else { return }
        let workspace = NSWorkspace.shared
        for name in [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.willSleepNotification,
        ] {
            lifecycleTokens.append(workspace.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main)
            { [weak self] _ in
                Task { @MainActor in self?.supervision.stopAll() }
            })
        }
        lifecycleTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor in self?.supervision.stopAll() }
        })
    }
}
