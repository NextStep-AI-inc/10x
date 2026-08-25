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

    private let clientFactory: ClientFactory
    private var handles: [String: Handle] = [:]
    private var exitWatchers: [String: Task<Void, Never>] = [:]

    private let exitStream: AsyncStream<UnexpectedExit>
    private let exitContinuation: AsyncStream<UnexpectedExit>.Continuation

    public struct UnexpectedExit: Sendable {
        public let sessionPath: String
        public let code: Int32?
        public let stderrTail: String
    }

    public init(clientFactory: @escaping ClientFactory = { RpcClient(configuration: $0) }) {
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

        var configuration = RpcClientConfiguration()
        configuration.cwd = URL(fileURLWithPath: cwd)
        configuration.resumeSessionPath = sessionPath
        let client = clientFactory(configuration)
        try await client.start()

        let handle = Handle(sessionPath: sessionPath, client: client)
        handles[sessionPath] = handle
        watchForExit(handle)
        return handle
    }

    /// Starts a fresh session in a project directory.
    public func openNew(projectDirectory: String) async throws -> Handle {
        var configuration = RpcClientConfiguration()
        configuration.cwd = URL(fileURLWithPath: projectDirectory)
        let client = clientFactory(configuration)
        try await client.start()

        let state = try? await client.send(.getState())
        let path = state?.data?["sessionFile"]?.stringValue
            ?? "new:\(projectDirectory):\(handles.count)"
        let handle = Handle(sessionPath: path, client: client)
        handles[path] = handle
        watchForExit(handle)
        return handle
    }

    public func close(sessionPath: String) async {
        guard let handle = handles.removeValue(forKey: sessionPath) else { return }
        exitWatchers.removeValue(forKey: sessionPath)?.cancel()
        await handle.client.shutdown()
    }

    public func closeAll() async {
        for path in handles.keys { await close(sessionPath: path) }
    }

    public func handle(for sessionPath: String) -> Handle? { handles[sessionPath] }

    /// The client's event stream finishing means its process is gone. If the
    /// session is still registered, nobody asked for that.
    private func watchForExit(_ handle: Handle) {
        exitWatchers[handle.sessionPath] = Task { [weak self] in
            for await _ in handle.client.events {}
            guard let self, !Task.isCancelled else { return }
            await self.reportExitIfStillOpen(handle)
        }
    }

    private func reportExitIfStillOpen(_ handle: Handle) async {
        guard handles[handle.sessionPath] != nil else { return }
        handles.removeValue(forKey: handle.sessionPath)
        exitWatchers.removeValue(forKey: handle.sessionPath)
        exitContinuation.yield(UnexpectedExit(
            sessionPath: handle.sessionPath,
            code: nil,
            stderrTail: await handle.client.stderrSnapshot()))
    }
}
