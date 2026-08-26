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

    public typealias ClientFactory = @Sendable (RpcClientConfiguration) -> RpcClient

    private let executable: String
    private let clientFactory: ClientFactory
    private var handles: [String: Handle] = [:]
    private var exitWatchers: [String: Task<Void, Never>] = [:]

    private struct Opening {
        let id: UUID
        let task: Task<Handle, any Error>
    }

    /// Opens in flight, so concurrent callers for one session share a child
    /// instead of racing across the `await` in `open`.
    private var opening: [String: Opening] = [:]

    private let exitStream: AsyncStream<UnexpectedExit>
    private let exitContinuation: AsyncStream<UnexpectedExit>.Continuation

    public struct UnexpectedExit: Sendable {
        public let sessionPath: String
        public let code: Int32?
        public let stderrTail: String
    }

    public init(
        executable: String = "omp",
        clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) }
    ) {
        self.executable = executable
        self.clientFactory = clientFactory
        (exitStream, exitContinuation) = AsyncStream<UnexpectedExit>.makeStream(
            bufferingPolicy: .unbounded)
    }

    /// Sessions whose child died without `close` being called — the UI's crash signal.
    public nonisolated var unexpectedExits: AsyncStream<UnexpectedExit> { exitStream }

    /// Opens a session, reusing the existing child when one is already running.
    @discardableResult
    public func open(sessionPath: String, cwd: String) async throws -> Handle {
        if let existing = handles[sessionPath] { return existing }
        // Join an open already under way rather than spawning a second child.
        if let inFlight = opening[sessionPath] { return try await inFlight.task.value }

        let factory = clientFactory
        let executable = executable
        let openingID = UUID()
        let task = Task { () throws -> Handle in
            var configuration = RpcClientConfiguration()
            configuration.executable = executable
            configuration.cwd = URL(fileURLWithPath: cwd)
            configuration.resumeSessionPath = sessionPath
            let client = factory(configuration)
            try await client.start()
            return Handle(sessionPath: sessionPath, client: client)
        }
        opening[sessionPath] = Opening(id: openingID, task: task)

        do {
            let handle = try await task.value
            guard opening[sessionPath]?.id == openingID else {
                throw CancellationError()
            }
            opening.removeValue(forKey: sessionPath)
            handles[sessionPath] = handle
            watchForExit(handle)
            return handle
        } catch {
            if opening[sessionPath]?.id == openingID {
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
        var configuration = RpcClientConfiguration()
        configuration.executable = executable
        configuration.cwd = URL(fileURLWithPath: projectDirectory)
        configuration.provider = provider
        configuration.model = model
        configuration.thinking = thinking
        let client = clientFactory(configuration)
        try await client.start()

        let state = try? await client.send(.getState())
        // A unique fallback key: a counter would collide with a live handle
        // after an earlier session was closed.
        let path = state?.data?["sessionFile"]?.stringValue
            ?? "new:\(projectDirectory):\(UUID().uuidString)"
        let handle = Handle(sessionPath: path, client: client)
        handles[path] = handle
        watchForExit(handle)
        return handle
    }

    public func close(sessionPath: String) async {
        let inFlight = opening.removeValue(forKey: sessionPath)
        inFlight?.task.cancel()
        let handle = handles.removeValue(forKey: sessionPath)
        exitWatchers.removeValue(forKey: sessionPath)?.cancel()
        if let handle { await handle.client.shutdown() }
        if let opened = try? await inFlight?.task.value {
            await opened.client.shutdown()
        }
    }

    public func closeAll() async {
        let paths = Set(handles.keys).union(opening.keys)
        for path in paths { await close(sessionPath: path) }
    }

    public func handle(for sessionPath: String) -> Handle? { handles[sessionPath] }

    /// Watches the dedicated termination signal — never `events`, which the app
    /// consumes and which an AsyncStream would not share.
    private func watchForExit(_ handle: Handle) {
        exitWatchers[handle.sessionPath] = Task { [weak self] in
            for await _ in handle.client.termination {}
            guard let self, !Task.isCancelled else { return }
            await self.reportExitIfStillOpen(handle)
        }
    }

    private func reportExitIfStillOpen(_ handle: Handle) async {
        guard let current = handles[handle.sessionPath], current.client === handle.client
        else { return }
        handles.removeValue(forKey: handle.sessionPath)
        exitWatchers.removeValue(forKey: handle.sessionPath)
        exitContinuation.yield(UnexpectedExit(
            sessionPath: handle.sessionPath,
            code: await handle.client.exitCode,
            stderrTail: await handle.client.stderrSnapshot()))
    }
}
