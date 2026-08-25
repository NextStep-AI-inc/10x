import Foundation

public enum RpcClientError: Error, Sendable {
    case notStarted
    case timeout(command: String)
    case processExited(code: Int32?, stderrTail: String)
    case commandFailed(command: String, error: String, code: String?)
    case startupFailed(String)
}

/// An error response that arrived with no request waiting for it — typically a
/// late failure for a prompt that was already acknowledged. Recorded rather
/// than thrown, since no caller is left to receive it.
public struct RpcProtocolError: Sendable, Equatable {
    public let command: String?
    public let requestId: String?
    public let remoteError: String?
}

public struct RpcClientConfiguration: Sendable {
    public var executable: String = "omp"
    /// Appended after the standard flags — or used as the entire argv when
    /// `rawArgv` is set.
    public var extraArguments: [String] = []
    /// Working directory of the child. This is the workspace its tools act on,
    /// so it must be the session's project directory.
    public var cwd: URL?
    public var resumeSessionPath: String?
    public var noSession: Bool = false
    public var environment: [String: String]?
    public var startupTimeout: Duration = .seconds(30)
    public var requestTimeout: Duration = .seconds(30)
    /// Test-only: when true, spawn arguments are `extraArguments` verbatim
    /// (no `--mode rpc` / `--no-title` / session flags prepended).
    public var rawArgv: Bool = false

    public init() {}

    var resolvedArguments: [String] {
        if rawArgv { return extraArguments }
        var args = ["--mode", "rpc", "--no-title"]
        if let resumeSessionPath {
            args += ["-r", resumeSessionPath]
        } else if noSession {
            args.append("--no-session")
        }
        args += extraArguments
        return args
    }
}

/// Speaks omp's newline-delimited RPC protocol over a spawned child process.
///
/// Responses are matched to requests by id — never by arrival order, since omp
/// dispatches some commands concurrently. Frame types the client does not know
/// are forwarded to `events` untouched, so a newer omp never breaks a session.
public actor RpcClient {
    private let configuration: RpcClientConfiguration
    private let transport: LineTransport

    private var pending: [String: CheckedContinuation<RpcResponse, any Error>] = [:]
    private var nextRequestNumber = 1
    private var reassembler: ChunkReassembler
    private var readerTask: Task<Void, Never>?
    private var started = false
    private var terminated = false

    private let eventStream: AsyncStream<RpcFrame>
    private let eventContinuation: AsyncStream<RpcFrame>.Continuation
    private var readyContinuation: CheckedContinuation<ReadyFrame, any Error>?
    /// The ready frame can arrive before `start()` registers its continuation,
    /// so it is held here and handed to whoever asks next.
    private var receivedReady: ReadyFrame?

    public private(set) var negotiatedProtocolVersion = 1
    public private(set) var protocolErrors: [RpcProtocolError] = []
    private static let maxProtocolErrors = 128

    public init(configuration: RpcClientConfiguration) {
        self.configuration = configuration
        self.transport = LineTransport(
            executable: configuration.executable,
            arguments: configuration.resolvedArguments,
            currentDirectory: configuration.cwd,
            environment: configuration.environment)
        self.reassembler = ChunkReassembler()
        (eventStream, eventContinuation) = AsyncStream<RpcFrame>.makeStream(
            bufferingPolicy: .unbounded)
    }

    /// Every frame that is not a command response: session events, extension UI
    /// requests, notices, and anything a future omp introduces.
    public nonisolated var events: AsyncStream<RpcFrame> { eventStream }

    /// Spawns the child, waits for its ready frame, and negotiates protocol v2
    /// when the server advertises it.
    @discardableResult
    public func start() async throws -> ReadyFrame {
        guard !started else { throw RpcClientError.startupFailed("already started") }
        started = true

        try await transport.start()
        startReader()

        let ready = try await withThrowingTaskGroup(of: ReadyFrame.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    Task { await self.setReadyContinuation(continuation) }
                }
            }
            group.addTask { [timeout = configuration.startupTimeout] in
                try await Task.sleep(for: timeout)
                throw RpcClientError.timeout(command: "ready")
            }
            do {
                let first = try await group.next()!
                group.cancelAll()
                return first
            } catch {
                await self.failReady(with: error)
                group.cancelAll()
                throw error
            }
        }

        if ready.supportedProtocolVersions?.contains(2) == true {
            let response = try await send(.negotiateProtocol(version: 2))
            if let version = response.data?["protocolVersion"]?.intValue {
                negotiatedProtocolVersion = version
            }
        }
        return ready
    }

    /// Sends a command and waits for the response carrying the same id.
    @discardableResult
    public func send(_ command: RpcCommand, timeout: Duration? = nil) async throws -> RpcResponse {
        guard started, !terminated else { throw RpcClientError.notStarted }
        let id = "req_\(nextRequestNumber)"
        nextRequestNumber += 1
        let line = try command.encodedLine(id: id)

        return try await withThrowingTaskGroup(of: RpcResponse.self) { group in
            group.addTask { [self] in
                try await withCheckedThrowingContinuation { continuation in
                    Task { await self.register(id: id, continuation: continuation, line: line) }
                }
            }
            group.addTask { [timeout = timeout ?? configuration.requestTimeout] in
                try await Task.sleep(for: timeout)
                throw RpcClientError.timeout(command: command.type)
            }
            do {
                let first = try await group.next()!
                group.cancelAll()
                return first
            } catch {
                // Resume the waiting continuation with the same error rather than
                // dropping it: an unresumed continuation would hang the group,
                // which awaits its children as the scope exits.
                await self.failPending(id: id, with: error)
                group.cancelAll()
                throw error
            }
        }
    }

    /// Writes a frame that receives no response (`extension_ui_response`).
    public func sendRaw(_ command: RpcCommand) async throws {
        guard started, !terminated else { throw RpcClientError.notStarted }
        try await transport.write(try command.encodedLine(id: "unused"))
    }

    public func stderrSnapshot() async -> String { await transport.stderrSnapshot() }

    public func shutdown() async {
        guard !terminated else { return }
        terminated = true
        await transport.shutdown()
        readerTask?.cancel()
        readerTask = nil
        failAllPending(
            exitCode: await transport.exitStatus,
            stderrTail: await transport.stderrSnapshot())
        eventContinuation.finish()
    }

    // MARK: - Reader

    private func startReader() {
        readerTask = Task { [weak self] in
            guard let self else { return }
            for await line in await self.transport.lines {
                await self.handle(line: line)
            }
            await self.handleStreamEnd()
        }
    }

    private func handle(line: Data) {
        let frame: RpcFrame
        do {
            frame = try RpcFrame.decode(line: line)
        } catch {
            // A malformed line is recoverable per the protocol: record and move on.
            record(RpcProtocolError(
                command: nil, requestId: nil,
                remoteError: "undecodable frame: \(error)"))
            return
        }

        if case .chunk(let chunk) = frame {
            do {
                if let payload = try reassembler.ingest(chunk) {
                    handle(line: payload)
                }
            } catch {
                record(RpcProtocolError(
                    command: nil, requestId: nil, remoteError: "chunk violation: \(error)"))
            }
            return
        }

        do {
            try reassembler.noteNonChunkFrame()
        } catch {
            record(RpcProtocolError(
                command: nil, requestId: nil, remoteError: "chunk sequence interrupted"))
        }

        switch frame {
        case .ready(let ready):
            if let readyContinuation {
                readyContinuation.resume(returning: ready)
                self.readyContinuation = nil
            } else {
                receivedReady = ready
            }
            eventContinuation.yield(frame)
        case .response(let response):
            deliver(response)
        case .chunk:
            break   // handled above
        case .extensionUIRequest, .event:
            eventContinuation.yield(frame)
        }
    }

    private func deliver(_ response: RpcResponse) {
        guard let id = response.id, let continuation = pending.removeValue(forKey: id) else {
            // No one is waiting: a late failure for an already-acked async
            // command, or an unknown-command reply with no id.
            if !response.success {
                record(RpcProtocolError(
                    command: response.command, requestId: response.id,
                    remoteError: response.error))
            }
            return
        }
        if response.success {
            continuation.resume(returning: response)
        } else {
            continuation.resume(throwing: RpcClientError.commandFailed(
                command: response.command,
                error: response.error ?? "unknown error",
                code: response.code))
        }
    }

    private func handleStreamEnd() async {
        guard !terminated else { return }
        failAllPending(
            exitCode: await transport.exitStatus,
            stderrTail: await transport.stderrSnapshot())
        eventContinuation.finish()
    }

    private func failAllPending(exitCode: Int32?, stderrTail: String) {
        for (_, continuation) in pending {
            continuation.resume(throwing: RpcClientError.processExited(
                code: exitCode, stderrTail: stderrTail))
        }
        pending.removeAll()
        if let readyContinuation {
            readyContinuation.resume(throwing: RpcClientError.processExited(
                code: exitCode, stderrTail: stderrTail))
            self.readyContinuation = nil
        }
    }

    private func record(_ error: RpcProtocolError) {
        protocolErrors.append(error)
        if protocolErrors.count > Self.maxProtocolErrors {
            protocolErrors.removeFirst(protocolErrors.count - Self.maxProtocolErrors)
        }
    }

    // MARK: - Continuation plumbing

    private func setReadyContinuation(_ continuation: CheckedContinuation<ReadyFrame, any Error>) {
        if let receivedReady {
            self.receivedReady = nil
            continuation.resume(returning: receivedReady)
            return
        }
        guard !terminated else {
            continuation.resume(throwing: RpcClientError.processExited(
                code: nil, stderrTail: ""))
            return
        }
        readyContinuation = continuation
    }

    private func register(
        id: String,
        continuation: CheckedContinuation<RpcResponse, any Error>,
        line: Data
    ) async {
        pending[id] = continuation
        do {
            try await transport.write(line)
        } catch {
            pending.removeValue(forKey: id)
            continuation.resume(throwing: RpcClientError.processExited(
                code: await transport.exitStatus,
                stderrTail: await transport.stderrSnapshot()))
        }
    }

    private func failPending(id: String, with error: any Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failReady(with error: any Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }
}
