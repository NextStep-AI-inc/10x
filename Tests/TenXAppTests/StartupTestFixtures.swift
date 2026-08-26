import Foundation
import OmpKit
import Synchronization
import Testing
@testable import TenXApp

actor CountingOmpLocator: OmpLocating {
    private let installation: OmpInstallation?
    private(set) var count = 0

    init(installation: OmpInstallation?) {
        self.installation = installation
    }

    func locate(preferredURL: URL?) async throws -> OmpInstallation? {
        count += 1
        try Task.checkCancellation()
        return installation
    }
}

actor StartupConfigRunner: OmpConfigRunning {
    private let startedGate: LoadGate?
    private let isFailing: Bool
    private var isBlocked: Bool

    init(
        startedGate: LoadGate? = nil,
        isFailing: Bool = false,
        isBlocked: Bool = false
    ) {
        self.startedGate = startedGate
        self.isFailing = isFailing
        self.isBlocked = isBlocked
    }

    func run(arguments: [String]) async throws -> Data {
        await startedGate?.started()
        if isBlocked {
            try await ContinuousClock().sleep(for: .seconds(60))
        }
        if isFailing { throw StartupFixtureError.config }
        if arguments == ["config", "path"] {
            return Data("/tmp/omp/config.json\n".utf8)
        }
        return Data(#"{"autoResume":{"value":false,"type":"boolean","description":"Automatically resume"}}"#.utf8)
    }

    func setBlocked(_ value: Bool) {
        isBlocked = value
    }
}

enum StartupFixtureError: Error, Sendable {
    case config
}

extension StartupTiming {
    static func controlledTimeout(_ gate: LoadGate) -> StartupTiming {
        let sleeper = ControlledStartupTimeout(gate: gate)
        return StartupTiming(
            minimumVisibility: .zero,
            timeout: .seconds(10),
            sleep: { duration in
                guard duration == .seconds(10) else { return }
                try await sleeper.sleep()
            })
    }
}

private actor ControlledStartupTimeout {
    private let gate: LoadGate
    private var invocationCount = 0

    init(gate: LoadGate) {
        self.gate = gate
    }

    func sleep() async throws {
        invocationCount += 1
        if invocationCount == 1 {
            await gate.started()
            await gate.waitForRelease()
        } else {
            try await ContinuousClock().sleep(for: .seconds(60))
        }
    }
}

@MainActor
func waitForModelState(
    _ predicate: @escaping @MainActor () async -> Bool
) async {
    for _ in 0..<200 {
        if await predicate() { return }
        try? await ContinuousClock().sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for startup fixture state")
}

@MainActor
func makeStartupDependencies(
    locator: any OmpLocating,
    library: SessionLibrary,
    defaults: UserDefaults,
    timing: StartupTiming,
    settingsRunner: any OmpConfigRunning,
    makeProviderModel: @escaping @MainActor @Sendable (URL) -> ProviderManagementViewModel,
    makeProcessManager: @escaping @Sendable (String) -> SessionProcessManager
) -> AppDependencies {
    AppDependencies(
        ompLocator: locator,
        sessionLibrary: library,
        recentProjectStore: RecentProjectStore(defaults: defaults),
        startupTiming: timing,
        makeProcessManager: makeProcessManager,
        makeSettingsModel: { _ in
            SettingsViewModel(service: OmpConfigService(runner: settingsRunner))
        },
        makeProviderModel: makeProviderModel)
}

@MainActor
final class StartupProviderModelFactory {
    private let models: [ProviderManagementViewModel]
    private(set) var count = 0

    init(models: [ProviderManagementViewModel]) {
        self.models = models
    }

    func next() -> ProviderManagementViewModel {
        let model = models[min(count, models.count - 1)]
        count += 1
        return model
    }
}

actor StartupRetentionGate {
    private var sleeper: (UUID, CheckedContinuation<Void, any Error>)?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleeper = (id, continuation)
                let waiters = startWaiters
                startWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func waitForStart() async {
        guard sleeper == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        let continuation = sleeper?.1
        sleeper = nil
        continuation?.resume()
    }

    private func cancel(id: UUID) {
        guard sleeper?.0 == id else { return }
        let continuation = sleeper?.1
        sleeper = nil
        continuation?.resume(throwing: CancellationError())
    }
}

private struct StartupProcessCaptureState: Sendable {
    var configurationCount = 0
    var clientsByProject: [String: RpcClient] = [:]
}

private final class StartupProcessCapture: Sendable {
    private let state = Mutex(StartupProcessCaptureState())

    func record(project: String, client: RpcClient) {
        state.withLock {
            $0.configurationCount += 1
            $0.clientsByProject[project] = client
        }
    }

    var configurationCount: Int {
        state.withLock { $0.configurationCount }
    }

    func client(project: String) -> RpcClient? {
        state.withLock { $0.clientsByProject[project] }
    }
}

@MainActor
final class StartupFixture {
    let root: URL
    let installation = OmpInstallation(
        executableURL: URL(filePath: "/usr/bin/true"),
        version: "test")
    let library: SessionLibrary

    private let sessionsRoot: URL
    private let archiveRoot: URL
    private let defaults: UserDefaults
    private let defaultsSuiteName: String
    private let fakeServerURL: URL
    private var mixedCapture = StartupProcessCapture()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StartupFixture-\(UUID().uuidString)", isDirectory: true)
        sessionsRoot = root.appendingPathComponent("sessions", isDirectory: true)
        archiveRoot = root.appendingPathComponent("archived-sessions", isDirectory: true)
        defaultsSuiteName = "StartupFixture.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            throw StartupFixtureError.config
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try FileManager.default.createDirectory(
            at: sessionsRoot,
            withIntermediateDirectories: true)
        library = SessionLibrary(root: sessionsRoot, archiveRoot: archiveRoot)
        fakeServerURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py")
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func project(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(_ name: String) -> URL {
        root.appendingPathComponent(name)
    }

    func writeSession(cwd: URL, modified: Date) throws {
        let bucket = sessionsRoot.appendingPathComponent("fixture", isDirectory: true)
        let file = bucket.appendingPathComponent("\(UUID().uuidString).jsonl")
        let identifier = UUID().uuidString
        let content = """
        {"type":"session","version":3,"id":"\(identifier)","timestamp":"2026-01-01T00:00:00.000Z","cwd":"\(cwd.path)"}
        {"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","content":"done"}}
        """
        try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: modified],
            ofItemAtPath: file.path)
    }

    func model(
        locator: (any OmpLocating)? = nil,
        processManager: SessionProcessManager? = nil,
        timing: StartupTiming = .live,
        settingsRunner: any OmpConfigRunning = StartupConfigRunner(),
        providerModel: ProviderManagementViewModel? = nil,
        providerFactory: StartupProviderModelFactory? = nil
    ) -> AppModel {
        let manager = processManager ?? self.processManager()
        let provider = providerModel ?? providerTestModel(providers: [
            ProviderLoginProvider(
                id: "cursor",
                name: "Cursor",
                isAvailable: true,
                isAuthenticated: true),
        ])
        let makeProvider: @MainActor @Sendable (URL) -> ProviderManagementViewModel
        if let providerFactory {
            makeProvider = { _ in providerFactory.next() }
        } else {
            makeProvider = { _ in provider }
        }
        let dependencies = makeStartupDependencies(
            locator: locator ?? CountingOmpLocator(installation: installation),
            library: library,
            defaults: defaults,
            timing: timing,
            settingsRunner: settingsRunner,
            makeProviderModel: makeProvider,
            makeProcessManager: { _ in manager })
        return AppModel(dependencies: dependencies, preferenceDefaults: defaults)
    }

    func processManager(
        modesByProject: [String: String] = [:]
    ) -> SessionProcessManager {
        let canonicalModes = Dictionary(uniqueKeysWithValues: modesByProject.map {
            (canonicalProject($0.key), $0.value)
        })
        return manager { project in
            (canonicalModes[project] ?? "basic", [])
        }
    }

    func retentionManager(gate: StartupRetentionGate) -> SessionProcessManager {
        manager(
            warmGracePeriod: .seconds(300),
            sleep: { duration in try await gate.sleep(for: duration) }) { _ in
                ("basic", [])
            }
    }

    func mixedWarmManager(
        readyProject: URL,
        stalledProject: URL
    ) -> SessionProcessManager {
        let ready = canonicalProject(readyProject.path)
        let stalled = canonicalProject(stalledProject.path)
        let capture = StartupProcessCapture()
        mixedCapture = capture
        return manager(capture: capture) { project in
            if project == stalled { return ("never-ready", []) }
            if project == ready { return ("basic", []) }
            return ("basic", [])
        }
    }

    var mixedWarmConfigurationCount: Int {
        mixedCapture.configurationCount
    }

    func mixedWarmClient(for project: URL) -> RpcClient? {
        mixedCapture.client(project: canonicalProject(project.path))
    }

    func triggeredCrashManager(
        project: URL,
        trigger: URL
    ) -> SessionProcessManager {
        let target = canonicalProject(project.path)
        return manager { current in
            current == target
                ? ("crash-after-trigger", [trigger.path])
                : ("basic", [])
        }
    }

    private func manager(
        capture: StartupProcessCapture = StartupProcessCapture(),
        warmGracePeriod: Duration = .seconds(300),
        sleep: @escaping SessionProcessManager.Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        },
        mode: @escaping @Sendable (String) -> (String, [String])
    ) -> SessionProcessManager {
        let fakeServerURL = fakeServerURL
        return SessionProcessManager(
            warmGracePeriod: warmGracePeriod,
            sleep: sleep,
            clientFactory: { configuration in
                let project = canonicalProject(configuration.cwd?.path ?? "")
                let selection = mode(project)
                var fake = configuration
                fake.executable = "/usr/bin/env"
                fake.extraArguments = ["python3", fakeServerURL.path, selection.0] + selection.1
                fake.rawArgv = true
                fake.cwd = nil
                fake.startupTimeout = .seconds(30)
                let client = RpcClient(configuration: fake)
                capture.record(project: project, client: client)
                return client
            })
    }
}

private func canonicalProject(_ path: String) -> String {
    URL(filePath: path, directoryHint: .isDirectory)
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
}
