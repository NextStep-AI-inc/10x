import Foundation

/// Owns one `omp --mode rpc` child per open session.
///
/// One process per session is the lifecycle omp's RPC server is built around:
/// it holds a single session and disposes of it when stdin closes. Each child
/// is spawned with the session's project directory as its cwd, since that is
/// the workspace its tools read and write.
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

    private struct Opening {
        let id: UUID
        let task: Task<ManagedHandle, any Error>
    }

    private struct WarmOpening {
        let id: UUID
        let task: Task<ManagedWarmHandle, any Error>
    }

    private let executable: String
    private let clientFactory: ClientFactory
    private var handles: [String: ManagedHandle] = [:]
    private var warmHandles: [String: ManagedWarmHandle] = [:]
    private var opening: [String: Opening] = [:]
    private var warming: [String: WarmOpening] = [:]
    private var terminationWatchers: [UUID: Task<Void, Never>] = [:]

    private let exitStream: AsyncStream<UnexpectedExit>
    private let exitContinuation: AsyncStream<UnexpectedExit>.Continuation
    private let warmExitStream: AsyncStream<WarmExit>
    private let warmExitContinuation: AsyncStream<WarmExit>.Continuation

    public init(
        executable: String = "omp",
        clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) }
    ) {
        self.executable = executable
        self.clientFactory = clientFactory
        (exitStream, exitContinuation) = AsyncStream<UnexpectedExit>.makeStream(
            bufferingPolicy: .unbounded)
        (warmExitStream, warmExitContinuation) = AsyncStream<WarmExit>.makeStream(
            bufferingPolicy: .unbounded)
    }

    deinit {
        exitContinuation.finish()
        warmExitContinuation.finish()
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
            return try await inFlight.task.value.handle
        }

        let factory = clientFactory
        let executable = executable
        let openingID = UUID()
        let task = Task { () throws -> ManagedHandle in
            var configuration = RpcClientConfiguration()
            configuration.executable = executable
            configuration.cwd = URL(fileURLWithPath: cwd)
            configuration.resumeSessionPath = sessionPath
            let client = factory(configuration)
            try await client.start()
            let managed = ManagedClient(id: UUID(), client: client)
            return ManagedHandle(
                managed: managed,
                handle: Handle(sessionPath: sessionPath, client: client))
        }
        opening[sessionPath] = Opening(id: openingID, task: task)

        do {
            let opened = try await task.value
            guard opening[sessionPath]?.id == openingID else {
                await opened.managed.client.shutdown()
                throw CancellationError()
            }
            opening.removeValue(forKey: sessionPath)
            handles[sessionPath] = opened
            watchForExit(opened.managed)
            return opened.handle
        } catch {
            if opening[sessionPath]?.id == openingID {
                opening.removeValue(forKey: sessionPath)
            }
            throw error
        }
    }

    /// Starts a fresh session in a project directory.
    public func openNew(projectDirectory: String) async throws -> Handle {
        var configuration = RpcClientConfiguration()
        configuration.executable = executable
        configuration.cwd = URL(fileURLWithPath: projectDirectory)
        let client = clientFactory(configuration)
        try await client.start()

        let state = try? await client.send(.getState())
        // A unique fallback key: a counter would collide with a live handle
        // after an earlier session was closed.
        let path = state?.data?["sessionFile"]?.stringValue
            ?? "new:\(projectDirectory):\(UUID().uuidString)"
        let managed = ManagedClient(id: UUID(), client: client)
        let opened = ManagedHandle(
            managed: managed,
            handle: Handle(sessionPath: path, client: client))
        handles[path] = opened
        watchForExit(managed)
        return opened.handle
    }

    /// Starts a no-session client for a project, reusing a ready or in-flight child.
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
        let task = Task { () throws -> ManagedWarmHandle in
            var configuration = RpcClientConfiguration()
            configuration.executable = executable
            configuration.cwd = URL(filePath: project, directoryHint: .isDirectory)
            configuration.noSession = true
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

    public func close(sessionPath: String) async {
        let inFlight = opening.removeValue(forKey: sessionPath)
        inFlight?.task.cancel()
        let handle = handles.removeValue(forKey: sessionPath)
        if let handle {
            terminationWatchers.removeValue(forKey: handle.managed.id)?.cancel()
            await handle.managed.client.shutdown()
        }
        if let opened = try? await inFlight?.task.value {
            await opened.managed.client.shutdown()
        }
    }

    public func closeAll() async {
        _ = await cancelWarmings()

        let paths = Set(handles.keys).union(opening.keys)
        for path in paths { await close(sessionPath: path) }

        let registeredWarmHandles = Array(warmHandles.values)
        warmHandles.removeAll()
        for warmHandle in registeredWarmHandles {
            terminationWatchers.removeValue(forKey: warmHandle.managed.id)?.cancel()
            await warmHandle.managed.client.shutdown()
        }

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

    private func completeWarmOpening(project: String, opening: WarmOpening) async throws
        -> WarmHandle {
        let opened = try await opening.task.value
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
        if let warm = warmHandles.first(where: { $0.value.managed.id == managed.id }) {
            warmHandles.removeValue(forKey: warm.key)
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
}
