import Foundation

/// Owns one OMP RPC child per open session.
///
/// One process per session is the lifecycle omp's RPC server is built around:
/// it holds a single session and disposes of it when stdin closes. Each child
/// is spawned with the session's project directory as its cwd, since that is
/// the workspace its tools read and write.
public enum SessionProcessManagerError: Error, Sendable, Equatable {
    case duplicateSessionPath(String)
    case missingSessionPath(String)
}

public actor SessionProcessManager {
    public struct Handle: Sendable {
        public let sessionPath: String
        public let client: RpcClient
    }

    public struct WarmHandle: Sendable {
        public let projectDirectory: String
        public let client: RpcClient
    }

    public struct UnexpectedExit: Sendable {
        public let sessionPath: String
        public let code: Int32?
        public let stderrTail: String
    }

    public struct WarmExit: Sendable {
        public let projectDirectory: String
        public let code: Int32?
        public let stderrTail: String
    }

    public typealias ClientFactory = @Sendable (RpcClientConfiguration) -> RpcClient
    public typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias WarmActivationHook = @Sendable () async -> Void
    typealias WarmRegistrationHook = @Sendable () async -> Void

    private struct ManagedClient: Sendable {
        let id: UUID
        let client: RpcClient
    }

    private struct ManagedHandle: Sendable {
        let managed: ManagedClient
        let handle: Handle
    }

    private struct ManagedWarmHandle: Sendable {
        let managed: ManagedClient
        let handle: WarmHandle
    }

    private final class OpenCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Handle, any Error>?
        private var waiters: [CheckedContinuation<Handle, any Error>] = []

        func wait() async throws -> Handle {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }

        func resolve(_ result: Result<Handle, any Error>) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let waiters = self.waiters
            self.waiters.removeAll()
            lock.unlock()
            for waiter in waiters { waiter.resume(with: result) }
        }
    }

    private struct Opening {
        let id: UUID
        let task: Task<ManagedHandle, any Error>
        let completion: OpenCompletion
    }

    private struct WarmOpening {
        let id: UUID
        let task: Task<ManagedWarmHandle, any Error>
    }

    private struct NewOpening {
        let id: UUID
        let task: Task<ManagedHandle, any Error>
    }

    private struct Transition {
        let openingID: UUID
        let managed: ManagedClient
        let sessionPath: String
    }

    private let executable: String
    /// Appended to every `RpcClientConfiguration` this actor builds — e.g. an
    /// App-layer `-e <extension path>` that must load on every `omp` spawn.
    private let extraArguments: [String]
    private let supportsUserInteraction: Bool
    private let warmGracePeriod: Duration
    private let sleep: Sleep
    private let clientFactory: ClientFactory
    private let beforeWarmActivation: WarmActivationHook?
    private let beforeWarmRegistration: WarmRegistrationHook?
    private var handles: [String: ManagedHandle] = [:]
    private var warmHandles: [String: ManagedWarmHandle] = [:]
    private var opening: [String: Opening] = [:]
    private var warming: [String: WarmOpening] = [:]
    private var newOpenings: [UUID: NewOpening] = [:]
    private var transitions: [UUID: Transition] = [:]
    private var warmExpiryTasks: [String: Task<Void, Never>] = [:]
    private var terminationWatchers: [UUID: Task<Void, Never>] = [:]

    private let exitStream: AsyncStream<UnexpectedExit>
    private let exitContinuation: AsyncStream<UnexpectedExit>.Continuation
    private let warmExitStream: AsyncStream<WarmExit>
    private let warmExitContinuation: AsyncStream<WarmExit>.Continuation

    public init(
        executable: String = "omp",
        extraArguments: [String] = [],
        supportsUserInteraction: Bool = false,
        warmGracePeriod: Duration = .seconds(300),
        sleep: @escaping Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        },
        clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) }
    ) {
        self.init(
            executable: executable,
            extraArguments: extraArguments,
            supportsUserInteraction: supportsUserInteraction,
            warmGracePeriod: warmGracePeriod,
            sleep: sleep,
            clientFactory: clientFactory,
            beforeWarmActivation: nil,
            beforeWarmRegistration: nil)
    }

    init(
        executable: String = "omp",
        extraArguments: [String] = [],
        supportsUserInteraction: Bool = false,
        warmGracePeriod: Duration = .seconds(300),
        sleep: @escaping Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        },
        clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) },
        beforeWarmActivation: WarmActivationHook?,
        beforeWarmRegistration: WarmRegistrationHook?
    ) {
        self.executable = executable
        self.extraArguments = extraArguments
        self.supportsUserInteraction = supportsUserInteraction
        self.warmGracePeriod = warmGracePeriod
        self.sleep = sleep
        self.clientFactory = clientFactory
        self.beforeWarmActivation = beforeWarmActivation
        self.beforeWarmRegistration = beforeWarmRegistration
        (exitStream, exitContinuation) = AsyncStream<UnexpectedExit>.makeStream(
            bufferingPolicy: .unbounded)
        (warmExitStream, warmExitContinuation) = AsyncStream<WarmExit>.makeStream(
            bufferingPolicy: .unbounded)
    }

    deinit {
        exitContinuation.finish()
        warmExitContinuation.finish()
        for expiry in warmExpiryTasks.values { expiry.cancel() }
        for watcher in terminationWatchers.values { watcher.cancel() }
    }

    /// Sessions whose child died without `close` being called — the UI's crash signal.
    public nonisolated var unexpectedExits: AsyncStream<UnexpectedExit> { exitStream }

    /// Warm project children that died before checkout.
    public nonisolated var unexpectedWarmExits: AsyncStream<WarmExit> { warmExitStream }

    /// Opens a session, reusing the existing child when one is already running.
    @discardableResult
    public func open(sessionPath: String, cwd: String) async throws -> Handle {
        if let existing = handles[sessionPath] { return existing.handle }
        // Join an open already under way rather than spawning a second child.
        if let inFlight = opening[sessionPath] {
            return try await inFlight.completion.wait()
        }
        if let warm = takeWarmClient(projectDirectory: cwd) {
            let openingID = UUID()
            beginTransition(
                managed: warm.managed,
                openingID: openingID,
                sessionPath: sessionPath)
            let task = Task { () throws -> ManagedHandle in
                try await self.checkOut(sessionPath: sessionPath, warm: warm)
            }
            let completion = OpenCompletion()
            opening[sessionPath] = Opening(id: openingID, task: task, completion: completion)

            do {
                let opened = try await task.value
                guard opening[sessionPath]?.id == openingID else {
                    await discardTransition(managed: opened.managed)
                    throw CancellationError()
                }
                await beforeWarmActivation?()
                guard let handle = try activateTransition(
                    managed: opened.managed,
                    openingID: openingID,
                    sessionPath: sessionPath
                ) else {
                    throw await transitionExitError(for: opened.managed)
                }
                completion.resolve(.success(handle))
                opening.removeValue(forKey: sessionPath)
                return handle
            } catch {
                if opening[sessionPath]?.id == openingID {
                    completion.resolve(.failure(error))
                    opening.removeValue(forKey: sessionPath)
                }
                await discardTransition(managed: warm.managed)
                throw error
            }
        }

        let factory = clientFactory
        let executable = executable
        let extraArguments = extraArguments
        let supportsUserInteraction = supportsUserInteraction
        let openingID = UUID()
        let task = Task { () throws -> ManagedHandle in
            var configuration = RpcClientConfiguration()
            configuration.executable = executable
            configuration.extraArguments = extraArguments
            configuration.supportsUserInteraction = supportsUserInteraction
            configuration.cwd = URL(fileURLWithPath: cwd)
            configuration.resumeSessionPath = sessionPath
            let client = factory(configuration)
            try await client.start()
            let managed = ManagedClient(id: UUID(), client: client)
            return ManagedHandle(
                managed: managed,
                handle: Handle(sessionPath: sessionPath, client: client))
        }
        let completion = OpenCompletion()
        opening[sessionPath] = Opening(id: openingID, task: task, completion: completion)

        do {
            let opened = try await task.value
            guard opening[sessionPath]?.id == openingID else {
                await opened.managed.client.shutdown()
                throw CancellationError()
            }
            handles[sessionPath] = opened
            watchForExit(opened.managed)
            completion.resolve(.success(opened.handle))
            opening.removeValue(forKey: sessionPath)
            return opened.handle
        } catch {
            if opening[sessionPath]?.id == openingID {
                completion.resolve(.failure(error))
                opening.removeValue(forKey: sessionPath)
            }
            throw error
        }
    }

    /// Starts a fresh session in a project directory.
    public func openNew(
        projectDirectory: String,
        provider: String? = nil,
        model: String? = nil,
        thinking: String? = nil
    ) async throws -> Handle {
        let openingID = UUID()
        let project = canonicalProjectDirectory(projectDirectory)
        let fallbackPath = "new:\(project):\(UUID().uuidString)"
        let sessionDirectory = freshSessionDirectory(for: project)
        let managed: ManagedClient
        let isWarmCheckout: Bool
        let task: Task<ManagedHandle, any Error>

        if let warm = takeWarmClient(projectDirectory: projectDirectory) {
            managed = warm.managed
            isWarmCheckout = true
            beginTransition(managed: managed, openingID: openingID, sessionPath: fallbackPath)
            task = Task { () throws -> ManagedHandle in
                _ = try await managed.client.send(.newSession(parentSession: nil))
                if let provider, let model {
                    _ = try await managed.client.send(.setModel(
                        provider: provider,
                        modelId: model))
                }
                if let thinking {
                    _ = try await managed.client.send(.setThinkingLevel(thinking))
                }
                let state = try await managed.client.send(.getState())
                guard let path = state.data?["sessionFile"]?.stringValue else {
                    throw SessionProcessManagerError.missingSessionPath(project)
                }
                return ManagedHandle(
                    managed: managed,
                    handle: Handle(sessionPath: path, client: managed.client))
            }
        } else {
            var configuration = RpcClientConfiguration()
            configuration.executable = executable
            configuration.extraArguments = extraArguments
            configuration.cwd = URL(fileURLWithPath: projectDirectory)
            configuration.provider = provider
            configuration.model = model
            configuration.thinking = thinking
            configuration.supportsUserInteraction = supportsUserInteraction
            configuration.extraArguments = ["--session-dir", sessionDirectory]
            let client = clientFactory(configuration)
            managed = ManagedClient(id: UUID(), client: client)
            isWarmCheckout = false
            beginTransition(managed: managed, openingID: openingID, sessionPath: fallbackPath)
            task = Task { () throws -> ManagedHandle in
                try await client.start()
                let state = try await client.send(.getState())
                guard let path = state.data?["sessionFile"]?.stringValue else {
                    throw SessionProcessManagerError.missingSessionPath(project)
                }
                return ManagedHandle(
                    managed: managed,
                    handle: Handle(sessionPath: path, client: client))
            }
        }
        newOpenings[openingID] = NewOpening(id: openingID, task: task)

        do {
            let opened = try await task.value
            guard newOpenings[openingID]?.id == openingID else {
                await discardTransition(managed: opened.managed)
                throw CancellationError()
            }
            if isWarmCheckout { await beforeWarmActivation?() }
            guard let handle = try activateTransition(
                managed: opened.managed,
                openingID: openingID,
                sessionPath: opened.handle.sessionPath
            ) else {
                throw await transitionExitError(for: opened.managed)
            }
            newOpenings.removeValue(forKey: openingID)
            if !isWarmCheckout { watchForExit(opened.managed) }
            return handle
        } catch {
            if newOpenings[openingID]?.id == openingID {
                newOpenings.removeValue(forKey: openingID)
            }
            await discardTransition(managed: managed)
            throw error
        }
    }

    /// Starts a fresh persistent client for a project, reusing a ready or in-flight child.
    @discardableResult
    public func warm(projectDirectory: String) async throws -> WarmHandle {
        let project = canonicalProjectDirectory(projectDirectory)
        if let existing = warmHandles[project] { return existing.handle }
        if let inFlight = warming[project] {
            return try await completeWarmOpening(project: project, opening: inFlight)
        }

        let openingID = UUID()
        let factory = clientFactory
        let executable = executable
        let extraArguments = extraArguments
        let supportsUserInteraction = supportsUserInteraction
        let sessionDirectory = freshSessionDirectory(for: project)
        let task = Task { () throws -> ManagedWarmHandle in
            var configuration = RpcClientConfiguration()
            configuration.executable = executable
            configuration.extraArguments = extraArguments
            configuration.supportsUserInteraction = supportsUserInteraction
            configuration.cwd = URL(filePath: project, directoryHint: .isDirectory)
            configuration.extraArguments = ["--session-dir", sessionDirectory]
            let client = factory(configuration)
            try await client.start()
            let managed = ManagedClient(id: UUID(), client: client)
            return ManagedWarmHandle(
                managed: managed,
                handle: WarmHandle(projectDirectory: project, client: client))
        }
        warming[project] = WarmOpening(id: openingID, task: task)

        do {
            return try await completeWarmOpening(
                project: project,
                opening: WarmOpening(id: openingID, task: task))
        } catch {
            if warming[project]?.id == openingID {
                warming.removeValue(forKey: project)
            }
            throw error
        }
    }

    public func isWarm(projectDirectory: String) -> Bool {
        warmHandles[canonicalProjectDirectory(projectDirectory)] != nil
    }

    /// Retains the primary warm client and expires all others after the grace period.
    public func beginWarmRetention(primaryProjectDirectory: String?) {
        let primary = primaryProjectDirectory.map(canonicalProjectDirectory)
        if let primary {
            warmExpiryTasks.removeValue(forKey: primary)?.cancel()
        }
        for (project, warm) in warmHandles where project != primary {
            let managedID = warm.managed.id
            warmExpiryTasks[project]?.cancel()
            warmExpiryTasks[project] = Task { [weak self, sleep, warmGracePeriod] in
                do { try await sleep(warmGracePeriod) } catch { return }
                await self?.expireWarmClient(project: project, managedID: managedID)
            }
        }
    }

    @discardableResult
    public func evictWarmClients() async -> [String] {
        let projects = warmHandles.keys.sorted()
        for project in projects { await closeWarm(projectDirectory: project) }
        return projects
    }

    public func close(sessionPath: String) async {
        let inFlight = opening.removeValue(forKey: sessionPath)
        inFlight?.task.cancel()
        inFlight?.completion.resolve(.failure(CancellationError()))
        if let inFlight { await closeTransitions(openingID: inFlight.id) }
        let handle = handles.removeValue(forKey: sessionPath)
        if let handle {
            terminationWatchers.removeValue(forKey: handle.managed.id)?.cancel()
            await handle.managed.client.shutdown()
        }
        if let opened = try? await inFlight?.task.value {
            terminationWatchers.removeValue(forKey: opened.managed.id)?.cancel()
            await opened.managed.client.shutdown()
        }
    }

    public func closeAll() async {
        _ = await cancelWarmings()

        let pendingNewOpenings = Array(newOpenings.values)
        newOpenings.removeAll()
        for opening in pendingNewOpenings { opening.task.cancel() }

        let paths = Set(handles.keys).union(opening.keys)
        for path in paths { await close(sessionPath: path) }

        let pendingTransitions = Array(transitions.values)
        transitions.removeAll()
        for transition in pendingTransitions {
            terminationWatchers.removeValue(forKey: transition.managed.id)?.cancel()
            await transition.managed.client.shutdown()
        }
        for opening in pendingNewOpenings {
            if let opened = try? await opening.task.value {
                terminationWatchers.removeValue(forKey: opened.managed.id)?.cancel()
                await opened.managed.client.shutdown()
            }
        }

        for expiry in warmExpiryTasks.values { expiry.cancel() }
        warmExpiryTasks.removeAll()
        let warmProjects = Array(warmHandles.keys)
        for project in warmProjects { await closeWarm(projectDirectory: project) }

        for watcher in terminationWatchers.values { watcher.cancel() }
        terminationWatchers.removeAll()
    }

    @discardableResult
    public func cancelWarmings() async -> [String] {
        let projects = warming.keys.sorted()
        let openings = Array(warming.values)
        warming.removeAll()
        for opening in openings { opening.task.cancel() }
        for opening in openings {
            if let opened = try? await opening.task.value {
                await opened.managed.client.shutdown()
            }
        }
        return projects
    }

    public func handle(for sessionPath: String) -> Handle? { handles[sessionPath]?.handle }

    private func takeWarmClient(projectDirectory: String) -> ManagedWarmHandle? {
        let project = canonicalProjectDirectory(projectDirectory)
        warmExpiryTasks.removeValue(forKey: project)?.cancel()
        return warmHandles.removeValue(forKey: project)
    }

    private func checkOut(
        sessionPath: String,
        warm: ManagedWarmHandle
    ) async throws -> ManagedHandle {
        _ = try await warm.managed.client.send(.switchSession(path: sessionPath))
        let handle = Handle(sessionPath: sessionPath, client: warm.managed.client)
        return ManagedHandle(managed: warm.managed, handle: handle)
    }

    private func beginTransition(
        managed: ManagedClient,
        openingID: UUID,
        sessionPath: String
    ) {
        transitions[managed.id] = Transition(
            openingID: openingID,
            managed: managed,
            sessionPath: sessionPath)
    }

    private func activateTransition(
        managed: ManagedClient,
        openingID: UUID,
        sessionPath: String
    ) throws -> Handle? {
        guard transitions[managed.id]?.openingID == openingID else { return nil }
        guard handles[sessionPath] == nil else {
            throw SessionProcessManagerError.duplicateSessionPath(sessionPath)
        }
        transitions.removeValue(forKey: managed.id)
        let handle = Handle(sessionPath: sessionPath, client: managed.client)
        handles[sessionPath] = ManagedHandle(managed: managed, handle: handle)
        return handle
    }

    private func discardTransition(managed: ManagedClient) async {
        guard transitions.removeValue(forKey: managed.id) != nil else { return }
        terminationWatchers.removeValue(forKey: managed.id)?.cancel()
        await managed.client.shutdown()
    }

    private func closeTransitions(openingID: UUID) async {
        let matching = transitions.values.filter { $0.openingID == openingID }
        for transition in matching {
            transitions.removeValue(forKey: transition.managed.id)
            terminationWatchers.removeValue(forKey: transition.managed.id)?.cancel()
            await transition.managed.client.shutdown()
        }
    }

    private func transitionExitError(for managed: ManagedClient) async -> RpcClientError {
        .processExited(
            code: await managed.client.exitCode,
            stderrTail: await managed.client.stderrSnapshot())
    }

    private func expireWarmClient(project: String, managedID: UUID) async {
        guard warmHandles[project]?.managed.id == managedID else { return }
        await closeWarm(projectDirectory: project)
    }

    private func closeWarm(projectDirectory: String) async {
        let project = canonicalProjectDirectory(projectDirectory)
        warmExpiryTasks.removeValue(forKey: project)?.cancel()
        guard let warm = warmHandles.removeValue(forKey: project) else { return }
        terminationWatchers.removeValue(forKey: warm.managed.id)?.cancel()
        await warm.managed.client.shutdown()
    }

    private func completeWarmOpening(project: String, opening: WarmOpening) async throws
        -> WarmHandle {
        let opened = try await opening.task.value
        await beforeWarmRegistration?()
        if let existing = warmHandles[project], existing.managed.id == opened.managed.id {
            return existing.handle
        }
        guard warming[project]?.id == opening.id else {
            await opened.managed.client.shutdown()
            throw CancellationError()
        }
        warming.removeValue(forKey: project)
        warmHandles[project] = opened
        watchForExit(opened.managed)
        return opened.handle
    }

    /// Watches the dedicated termination signal — never `events`, which the app
    /// consumes and which an AsyncStream would not share.
    private func watchForExit(_ managed: ManagedClient) {
        terminationWatchers[managed.id] = Task { [weak self] in
            for await _ in managed.client.termination {}
            guard let self, !Task.isCancelled else { return }
            await self.reportExit(managed)
        }
    }

    private func reportExit(_ managed: ManagedClient) async {
        if let transition = transitions.removeValue(forKey: managed.id) {
            terminationWatchers.removeValue(forKey: managed.id)
            exitContinuation.yield(UnexpectedExit(
                sessionPath: transition.sessionPath,
                code: await managed.client.exitCode,
                stderrTail: await managed.client.stderrSnapshot()))
            return
        }
        if let warm = warmHandles.first(where: { $0.value.managed.id == managed.id }) {
            warmHandles.removeValue(forKey: warm.key)
            warmExpiryTasks.removeValue(forKey: warm.key)?.cancel()
            terminationWatchers.removeValue(forKey: managed.id)
            warmExitContinuation.yield(WarmExit(
                projectDirectory: warm.key,
                code: await managed.client.exitCode,
                stderrTail: await managed.client.stderrSnapshot()))
            return
        }

        guard let active = handles.first(where: { $0.value.managed.id == managed.id }) else {
            return
        }
        handles.removeValue(forKey: active.key)
        terminationWatchers.removeValue(forKey: managed.id)
        exitContinuation.yield(UnexpectedExit(
            sessionPath: active.key,
            code: await managed.client.exitCode,
            stderrTail: await managed.client.stderrSnapshot()))
    }

    private func canonicalProjectDirectory(_ projectDirectory: String) -> String {
        URL(filePath: projectDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func freshSessionDirectory(for projectDirectory: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent/sessions")
            .appendingPathComponent(SessionPathEncoding.bucketName(forCwd: projectDirectory))
            .path
    }
}
