import Foundation

public enum RpcClientError: Error, Sendable {
    case notStarted
    case timeout(command: String)
    case processExited(code: Int32?, stderrTail: String)
    case commandFailed(command: String, error: String, code: String?)
    case startupFailed(String)
}

/// A response plus the number of event frames that preceded it on stdout.
///
/// The owner of ``RpcClient/events`` can use this as an explicit delivery
/// fence: consume this many frames before applying the response when stdout
/// order matters across the event and response channels.
public struct RpcResponseEventFence: Sendable, Equatable {
    public let response: RpcResponse
    public let precedingEventCount: UInt64

    public init(response: RpcResponse, precedingEventCount: UInt64) {
        self.response = response
        self.precedingEventCount = precedingEventCount
    }
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
    public var provider: String?
    public var model: String?
    public var thinking: String?
    public var environment: [String: String]?
    public var startupTimeout: Duration = .seconds(30)
    public var requestTimeout: Duration = .seconds(30)
    /// Enables OMP tools that can pause for host-provided user input.
    public var supportsUserInteraction: Bool = false
    /// Test-only: when true, spawn arguments are `extraArguments` verbatim
    /// (no `--mode rpc` / `--no-title` / session flags prepended).
    public var rawArgv: Bool = false

    public init() {}

    var resolvedArguments: [String] {
        if rawArgv { return extraArguments }
        let mode = supportsUserInteraction ? "rpc-ui" : "rpc"
        var args = ["--mode", mode, "--no-title"]
        if let provider { args += ["--provider", provider] }
        if let model { args += ["--model", model] }
        if let thinking { args += ["--thinking", thinking] }
        if let resumeSessionPath {
            args += ["-r", resumeSessionPath]
        } else if noSession {
            args.append("--no-session")
        }
        args += extraArguments
        return args
    }
}

struct RpcClientTestHooks: Sendable {
    var beforeWaitForReady: (@Sendable () async -> Void)?
    var readyTimeoutSleep: (@Sendable (Duration) async throws -> Void)?

    init() {}
}

/// Speaks omp's newline-delimited RPC protocol over a spawned child process.
///
/// Responses are matched to requests by id — never by arrival order, since omp
/// dispatches some commands concurrently. Frame types the client does not know
/// are forwarded to `events` untouched, so a newer omp never breaks a session.
public actor RpcClient {
    private let configuration: RpcClientConfiguration
    private let transport: LineTransport
    private let testHooks: RpcClientTestHooks

    private struct PendingRequest {
        let command: String
        let continuation: CheckedContinuation<RpcResponseEventFence, any Error>
        var timeoutTask: Task<Void, Never>?
    }

    private var pending: [String: PendingRequest] = [:]
    private var nextRequestNumber = 1
    private var reassembler: ChunkReassembler
    private var readerTask: Task<Void, Never>?
    private var started = false
    private var terminated = false
    private var authoritativeExitCode: Int32?
    private var awaitingAuthoritativeExit = false
    private var observedExitRelatedWriteFailures = 0
    private var observedReadyTimeoutAttempts = 0

    private let eventStream: AsyncStream<RpcFrame>
    private let eventContinuation: AsyncStream<RpcFrame>.Continuation
    /// Separate from `events` so observers watching for the child's death do not
    /// consume frames the UI needs — an AsyncStream has a single consumer.
    private let terminationStream: AsyncStream<Void>
    private let terminationContinuation: AsyncStream<Void>.Continuation
    private var readyContinuation: CheckedContinuation<ReadyFrame, any Error>?
    private var readyTimeoutTask: Task<Void, Never>?
    /// The ready frame can arrive before `start()` registers its continuation,
    /// so it is held here and handed to whoever asks next.
    private var receivedReady: ReadyFrame?
    private var protocolV2Enabled = false
    private var streamsFinished = false
    private var yieldedEventCount: UInt64 = 0

    public private(set) var negotiatedProtocolVersion = 1
    public private(set) var protocolErrors: [RpcProtocolError] = []
    private static let maxProtocolErrors = 128

    /// Internal lifecycle seams used by deterministic transport-order tests.
    var isAwaitingAuthoritativeExit: Bool { awaitingAuthoritativeExit }
    var exitRelatedWriteFailureCount: Int { observedExitRelatedWriteFailures }
    var readyTimeoutAttemptCount: Int { observedReadyTimeoutAttempts }
    var hasReadyWaiter: Bool { readyContinuation != nil }
    var isReadyTimeoutArmed: Bool { readyTimeoutTask != nil }

    public init(configuration: RpcClientConfiguration) {
        self.init(configuration: configuration, testHooks: RpcClientTestHooks())
    }

    init(configuration: RpcClientConfiguration, testHooks: RpcClientTestHooks) {
        self.configuration = configuration
        self.testHooks = testHooks
        self.transport = LineTransport(
            executable: configuration.executable,
            arguments: configuration.resolvedArguments,
            currentDirectory: configuration.cwd,
            environment: configuration.environment)
        self.reassembler = ChunkReassembler()
        (eventStream, eventContinuation) = AsyncStream<RpcFrame>.makeStream(
            bufferingPolicy: .unbounded)
        (terminationStream, terminationContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
    }

    /// Every frame that is not a command response: session events, extension UI
    /// requests, notices, and anything a future omp introduces.
    ///
    /// Single-consumer, like any AsyncStream — one owner should iterate it.
    public nonisolated var events: AsyncStream<RpcFrame> { eventStream }

    /// Finishes when the child process is gone, for whatever reason. Watch this
    /// rather than `events` to observe termination without stealing frames.
    public nonisolated var termination: AsyncStream<Void> { terminationStream }

    /// Spawns the child, waits for its ready frame, and negotiates protocol v2
    /// when the server advertises it.
    @discardableResult
    public func start() async throws -> ReadyFrame {
        guard !started else { throw RpcClientError.startupFailed("already started") }
        started = true

        do {
            return try await performStart()
        } catch {
            // Never leave a spawned child behind on a failed startup.
            await shutdown()
            throw error
        }
    }

    private func performStart() async throws -> ReadyFrame {
        try await transport.start()
        startReader()
        await testHooks.beforeWaitForReady?()

        let ready = try await waitForReady()

        // Only negotiate v2 when the server's transport limits match the ones
        // this client enforces; a server with different bounds would produce
        // sequences the reassembler is not configured for, so v1 is safer.
        let limitsMatch = ready.maxFrameBytes == ChunkReassembler.maxPhysicalFrameBytes
            && ready.maxReassembledFrameBytes == ChunkReassembler.maxReassembledFrameBytes
        if ready.supportedProtocolVersions?.contains(2) == true, limitsMatch {
            // The negotiation response itself may be chunked. Permit chunks
            // only after the peer advertised v2 with the exact shared bounds.
            protocolV2Enabled = true
            let response = try await send(.negotiateProtocol(version: 2))
            guard let version = response.data?["protocolVersion"]?.intValue, version == 2 else {
                throw RpcClientError.startupFailed(
                    "server accepted negotiate_protocol without confirming v2")
            }
            negotiatedProtocolVersion = version
        }
        return ready
    }

    /// Sends a command and waits for the response carrying the same id.
    @discardableResult
    public func send(_ command: RpcCommand, timeout: Duration? = nil) async throws -> RpcResponse {
        let receipt = try await sendWithEventFence(command, timeout: timeout)
        let response = receipt.response
        guard response.success else {
            throw RpcClientError.commandFailed(
                command: response.command,
                error: response.error ?? "unknown error",
                code: response.code)
        }
        return response
    }

    /// Sends a command while retaining stdout ordering relative to `events`.
    ///
    /// `precedingEventCount` is captured when the response frame is decoded,
    /// after every earlier event frame has been yielded to the event stream.
    /// Command-failure responses are returned, not thrown, so callers that need
    /// the fence can still order failure handling behind earlier events.
    public func sendWithEventFence(
        _ command: RpcCommand,
        timeout: Duration? = nil
    ) async throws -> RpcResponseEventFence {
        guard started, !terminated else { throw RpcClientError.notStarted }
        let id = "req_\(nextRequestNumber)"
        nextRequestNumber += 1
        let line = try command.encodedLine(id: id)

        let requestTimeout = timeout ?? configuration.requestTimeout
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending[id] = PendingRequest(
                    command: command.type,
                    continuation: continuation,
                    timeoutTask: nil)
                if !awaitingAuthoritativeExit {
                    let timeoutTask = Task { [weak self] in
                        do { try await Task.sleep(for: requestTimeout) }
                        catch { return }
                        await self?.timeoutPending(id: id, command: command.type)
                    }
                    pending[id]?.timeoutTask = timeoutTask
                }
                Task { [weak self] in
                    await self?.write(line, for: id)
                }
            }
        } onCancel: {
            Task { await self.failPending(id: id, with: CancellationError()) }
        }
    }

    /// Writes a frame that receives no response (`extension_ui_response`).
    public func sendRaw(_ command: RpcCommand) async throws {
        guard started, !terminated else { throw RpcClientError.notStarted }
        try await transport.write(try command.encodedLine(id: "unused"))
    }

    public func stderrSnapshot() async -> String { await transport.stderrSnapshot() }

    /// The child's exit code once it has exited, nil while it is running.
    public var exitCode: Int32? {
        get async {
            if let authoritativeExitCode { return authoritativeExitCode }
            return await transport.exitStatus
        }
    }

    public func shutdown() async {
        if !terminated {
            terminated = true
            awaitingAuthoritativeExit = false
            failAllPending(
                exitCode: await transport.exitStatus,
                stderrTail: await transport.stderrSnapshot())
        }
        await transport.shutdown()
        readerTask?.cancel()
        readerTask = nil
        finishStreams()
    }

    /// A corrupted frame stream cannot be trusted for anything that follows, so
    /// the session is torn down rather than silently continuing with a partial
    /// transcript.
    private func poison(reason: String) async {
        record(RpcProtocolError(command: nil, requestId: nil, remoteError: reason))
        guard !terminated else { return }
        terminated = true
        awaitingAuthoritativeExit = false
        failAllPending(
            exitCode: await transport.exitStatus,
            stderrTail: await transport.stderrSnapshot())
        await transport.shutdown()
        readerTask?.cancel()
        readerTask = nil
        finishStreams()
    }

    private func finishStreams() {
        guard !streamsFinished else { return }
        streamsFinished = true
        eventContinuation.finish()
        terminationContinuation.yield(())
        terminationContinuation.finish()
    }

    // MARK: - Reader

    private func startReader() {
        readerTask = Task { [weak self] in
            guard let self else { return }
            for await line in self.transport.lines {
                await self.handle(line: line)
            }
            await self.didDrainStdout()
            for await exitCode in self.transport.onExit {
                await self.handleStreamEnd(
                    exitCode: exitCode,
                    stderrTail: await self.transport.stderrSnapshot())
                return
            }
        }
    }

    private func didDrainStdout() {
        guard !terminated else { return }
        awaitingAuthoritativeExit = true
        for id in Array(pending.keys) {
            pending[id]?.timeoutTask?.cancel()
            pending[id]?.timeoutTask = nil
        }
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
    }

    private func handle(line: Data) async {
        let frame: RpcFrame
        do {
            frame = try RpcFrame.decode(line: line)
        } catch {
            await poison(reason: "undecodable frame: \(error)")
            return
        }

        if case .chunk(let chunk) = frame {
            guard protocolV2Enabled else {
                await poison(reason: "chunk received before protocol negotiation")
                return
            }
            do {
                if let payload = try reassembler.ingest(chunk) {
                    await handle(line: payload)
                }
            } catch {
                await poison(reason: "chunk violation: \(error)")
            }
            return
        }

        do {
            try reassembler.noteNonChunkFrame()
        } catch {
            await poison(reason: "chunk sequence interrupted")
            return
        }

        switch frame {
        case .ready(let ready):
            if let readyContinuation {
                readyTimeoutTask?.cancel()
                readyTimeoutTask = nil
                readyContinuation.resume(returning: ready)
                self.readyContinuation = nil
            } else {
                receivedReady = ready
            }
            yieldEvent(frame)
        case .response(let response):
            deliver(response)
        case .chunk:
            break   // handled above
        case .extensionUIRequest, .providerAccountChanged, .event:
            yieldEvent(frame)
        }
    }

    private func yieldEvent(_ frame: RpcFrame) {
        yieldedEventCount &+= 1
        eventContinuation.yield(frame)
    }

    private func deliver(_ response: RpcResponse) {
        var request = response.id.flatMap { pending.removeValue(forKey: $0) }

        // omp answers an unrecognized command with `id: undefined`, so an
        // id-less failure still belongs to a waiter — match it by command name
        // rather than leaving the caller to time out.
        if request == nil, response.id == nil, !response.success {
            let matching = pending.filter { $0.value.command == response.command }
            if matching.count == 1, let key = matching.first?.key {
                request = pending.removeValue(forKey: key)
            } else if response.command == "parse", pending.count == 1,
                      let key = pending.first?.key {
                request = pending.removeValue(forKey: key)
            }
        }

        guard let request else {
            // Nobody is waiting: typically a late failure for a prompt that was
            // already acknowledged.
            if !response.success {
                record(RpcProtocolError(
                    command: response.command, requestId: response.id,
                    remoteError: response.error))
            }
            return
        }
        request.timeoutTask?.cancel()

        request.continuation.resume(returning: RpcResponseEventFence(
            response: response,
            precedingEventCount: yieldedEventCount))
    }

    private func handleStreamEnd(exitCode: Int32, stderrTail: String) {
        guard !terminated else { return }
        awaitingAuthoritativeExit = false
        authoritativeExitCode = exitCode
        terminated = true
        failAllPending(exitCode: exitCode, stderrTail: stderrTail)
        finishStreams()
    }

    private func failAllPending(exitCode: Int32?, stderrTail: String) {
        let outstanding = pending
        pending.removeAll()
        for (_, request) in outstanding {
            request.timeoutTask?.cancel()
            request.continuation.resume(throwing: RpcClientError.processExited(
                code: exitCode, stderrTail: stderrTail))
        }
        if let readyContinuation {
            readyTimeoutTask?.cancel()
            readyTimeoutTask = nil
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

    private func waitForReady() async throws -> ReadyFrame {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
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
                if !awaitingAuthoritativeExit {
                    readyTimeoutTask = Task {
                        [weak self, timeout = configuration.startupTimeout,
                         readyTimeoutSleep = testHooks.readyTimeoutSleep] in
                        do {
                            if let readyTimeoutSleep {
                                try await readyTimeoutSleep(timeout)
                            } else {
                                try await Task.sleep(for: timeout)
                            }
                        }
                        catch { return }
                        await self?.timeoutReady()
                    }
                }
            }
        } onCancel: {
            Task { await self.failReady(with: CancellationError()) }
        }
    }

    private func write(_ line: Data, for id: String) async {
        do {
            try await transport.write(line)
        } catch TransportError.closed {
            observedExitRelatedWriteFailures += 1
            // The reader owns exit arbitration. Keep the waiter pending so a
            // closed pipe cannot beat the authoritative onExit status.
        } catch {
            failPending(id: id, with: RpcClientError.processExited(
                code: await transport.exitStatus,
                stderrTail: await transport.stderrSnapshot()))
        }
    }

    private func timeoutPending(id: String, command: String) {
        guard !terminated, !awaitingAuthoritativeExit else { return }
        failPending(id: id, with: RpcClientError.timeout(command: command))
    }

    private func failPending(id: String, with error: any Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask?.cancel()
        request.continuation.resume(throwing: error)
    }

    private func failReady(with error: any Error) {
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func timeoutReady() {
        observedReadyTimeoutAttempts += 1
        guard !terminated, !awaitingAuthoritativeExit else { return }
        failReady(with: RpcClientError.timeout(command: "ready"))
    }
}
