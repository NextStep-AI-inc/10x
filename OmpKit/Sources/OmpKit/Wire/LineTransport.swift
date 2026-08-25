import Darwin
import Foundation

public enum TransportError: Error, Sendable, Equatable {
    case closed
    case spawnFailed(String)
    case notStarted
    case backlogOverflow
}

struct ProcessIdentity: Hashable, Sendable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct ProcessSnapshot: Sendable, Equatable {
    let identity: ProcessIdentity
    let parentPID: pid_t
    let processGroupID: pid_t
}

struct ProcessPIDList: Sendable {
    let pids: [pid_t]
    let isComplete: Bool
}

struct ProcessOperations: Sendable {
    let snapshot: @Sendable (pid_t) -> ProcessSnapshot?
    let childPIDs: @Sendable (pid_t) -> ProcessPIDList
    let groupPIDs: @Sendable (pid_t) -> ProcessPIDList
    let signalProcess: @Sendable (pid_t, Int32) -> Void
    let signalGroup: @Sendable (pid_t, Int32) -> Void

    static let live = ProcessOperations(
        snapshot: { pid in
            var info = proc_bsdinfo()
            let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let actualSize = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedSize)
            }
            guard actualSize == expectedSize, pid_t(info.pbi_pid) == pid else { return nil }
            return ProcessSnapshot(
                identity: ProcessIdentity(
                    pid: pid,
                    startSeconds: info.pbi_start_tvsec,
                    startMicroseconds: info.pbi_start_tvusec),
                parentPID: pid_t(info.pbi_ppid),
                processGroupID: pid_t(info.pbi_pgid))
        },
        childPIDs: { pid in processList { buffer, size in
            proc_listchildpids(pid, buffer, size)
        } },
        groupPIDs: { group in processList { buffer, size in
            proc_listpgrppids(group, buffer, size)
        } },
        signalProcess: { pid, signal in _ = kill(pid, signal) },
        signalGroup: { group, signal in _ = killpg(group, signal) })
}

private let maximumProcessListCount = 4_096

private func processList(
    _ list: (_ buffer: UnsafeMutableRawPointer?, _ size: Int32) -> Int32
) -> ProcessPIDList {
    var pids = [pid_t](repeating: 0, count: maximumProcessListCount)
    let count = pids.withUnsafeMutableBytes { buffer in
        list(buffer.baseAddress, Int32(buffer.count))
    }
    guard count >= 0 else { return ProcessPIDList(pids: [], isComplete: false) }
    let boundedCount = min(Int(count), pids.count)
    return ProcessPIDList(
        pids: Array(pids.prefix(boundedCount)),
        isComplete: Int(count) < pids.count)
}

/// Tracks only process identities observed as members of the original tree.
/// PIDs are revalidated by start time immediately before every signal.
struct ProcessTreeTracker: Sendable {
    static let maximumTrackedProcesses = maximumProcessListCount

    private let leader: ProcessIdentity
    private let processGroupID: pid_t?
    private let operations: ProcessOperations
    private var descendants: [pid_t: ProcessIdentity] = [:]
    private var hasCompleteObservation = false

    init(
        leader: ProcessSnapshot,
        processGroupID: pid_t?,
        operations: ProcessOperations
    ) {
        self.leader = leader.identity
        self.processGroupID = processGroupID
        self.operations = operations
    }

    var knownIdentityCount: Int { descendants.count }

    @discardableResult
    mutating func refresh(until deadline: ContinuousClock.Instant) -> Bool {
        var isComplete = true

        // Prune dead and reused identities. If the deadline interrupts this
        // pass, unchecked entries remain so termination cannot be confirmed.
        for identity in Array(descendants.values) {
            guard ContinuousClock.now < deadline else { return false }
            if operations.snapshot(identity.pid)?.identity != identity {
                descendants.removeValue(forKey: identity.pid)
            }
        }

        guard ContinuousClock.now < deadline else { return false }
        let liveLeader = exactSnapshot(for: leader)
        var pendingParents: [pid_t] = []
        if liveLeader != nil { pendingParents.append(leader.pid) }
        pendingParents.append(contentsOf: descendants.keys)
        var visited = Set(pendingParents)

        while let parent = pendingParents.popLast() {
            guard ContinuousClock.now < deadline else { return false }
            let children = operations.childPIDs(parent)
            isComplete = isComplete && children.isComplete
            for pid in children.pids where visited.insert(pid).inserted {
                guard ContinuousClock.now < deadline else { return false }
                guard let child = operations.snapshot(pid), child.parentPID == parent else { continue }
                if descendants.count < Self.maximumTrackedProcesses {
                    descendants[pid] = child.identity
                    pendingParents.append(pid)
                } else {
                    isComplete = false
                }
            }
        }

        if let processGroupID, hasOriginalGroupAnchor(
            processGroupID: processGroupID,
            deadline: deadline
        ) {
            guard ContinuousClock.now < deadline else { return false }
            let members = operations.groupPIDs(processGroupID)
            isComplete = isComplete && members.isComplete
            for pid in members.pids where pid != leader.pid {
                guard ContinuousClock.now < deadline else { return false }
                guard let member = operations.snapshot(pid),
                      member.processGroupID == processGroupID
                else { continue }
                if descendants.count < Self.maximumTrackedProcesses
                    || descendants[pid] != nil {
                    descendants[pid] = member.identity
                } else {
                    isComplete = false
                }
            }
        }
        let completed = isComplete && ContinuousClock.now < deadline
        if completed, liveLeader != nil { hasCompleteObservation = true }
        return completed
    }

    @discardableResult
    mutating func signal(
        _ signal: Int32,
        until deadline: ContinuousClock.Instant
    ) -> Bool {
        let isComplete = refresh(until: deadline)
        guard ContinuousClock.now < deadline else { return false }

        var didSignalGroup = false
        if let processGroupID,
           hasOriginalGroupAnchor(
               processGroupID: processGroupID,
               deadline: deadline) {
            guard ContinuousClock.now < deadline else { return false }
            operations.signalGroup(processGroupID, signal)
            didSignalGroup = true
        }

        let identities = [leader] + descendants.values
        for identity in identities {
            guard ContinuousClock.now < deadline else { return false }
            guard let current = exactSnapshot(for: identity) else {
                if identity != leader { descendants.removeValue(forKey: identity.pid) }
                continue
            }
            guard ContinuousClock.now < deadline else { return false }
            if !didSignalGroup || current.processGroupID != processGroupID {
                operations.signalProcess(identity.pid, signal)
            }
        }
        return isComplete
    }

    mutating func isTerminated(until deadline: ContinuousClock.Instant) -> Bool {
        guard refresh(until: deadline) else { return false }
        guard hasCompleteObservation else { return false }
        guard ContinuousClock.now < deadline else { return false }
        let liveLeader = exactSnapshot(for: leader)
        guard ContinuousClock.now < deadline, liveLeader == nil else { return false }
        return descendants.isEmpty
    }

    private func exactSnapshot(for identity: ProcessIdentity) -> ProcessSnapshot? {
        guard let snapshot = operations.snapshot(identity.pid), snapshot.identity == identity
        else { return nil }
        return snapshot
    }

    private func hasOriginalGroupAnchor(
        processGroupID: pid_t,
        deadline: ContinuousClock.Instant
    ) -> Bool {
        guard ContinuousClock.now < deadline else { return false }
        if let currentLeader = operations.snapshot(leader.pid) {
            // A different start time means the leader PID, and potentially its
            // numeric process-group ID, has been reused. Never group-signal it.
            guard currentLeader.identity == leader else { return false }
            if currentLeader.processGroupID == processGroupID { return true }
        }
        for identity in descendants.values {
            guard ContinuousClock.now < deadline else { return false }
            if exactSnapshot(for: identity)?.processGroupID == processGroupID { return true }
        }
        return false
    }
}

/// Newline-delimited byte transport over a child process's stdio.
///
/// Framing above this layer is JSON-per-line; this type only splits lines,
/// bounds the buffers, and owns process lifetime. Any line or delivery backlog
/// overflow fails the stream closed rather than discarding protocol frames.
public actor LineTransport {
    private let executable: String
    private let arguments: [String]
    private let currentDirectory: URL?
    private let environment: [String: String]?

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private var started = false
    private var stdinClosed = false
    private var processGroupID: pid_t?
    private var processTreeTracker: ProcessTreeTracker?
    private var stdoutDrainer: StdoutDrainer?
    private var descendantTrackerTask: Task<Void, Never>?
    private let processOperations: ProcessOperations
    private let trackerDidPoll: @Sendable () -> Void

    /// Read from the process itself so a crash reports its real code, not just
    /// exits observed on the shutdown path.
    public var exitStatus: Int32? {
        guard started, !process.isRunning else { return nil }
        return process.terminationStatus
    }

    /// stdin writes block when the child stops draining the pipe, so they run
    /// off the actor to avoid wedging every other call.
    private let writeQueue = DispatchQueue(label: "sh.omp.ompkit.stdin")

    private let lineStream: AsyncThrowingStream<Data, any Error>
    private let lineContinuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let exitStream: AsyncStream<Int32>
    private let exitContinuation: AsyncStream<Int32>.Continuation

    /// Guarded by `bufferLock` because the reader runs on a Foundation callback
    /// queue, outside the actor's executor.
    private let buffer = LineBuffer()
    private let stderrLog = StderrLog(maxChunks: 512)

    /// Slack over the protocol's 1 MiB physical frame cap before a line is
    /// considered runaway.
    private static let maxLineBytes = 1_048_576 + 65_536
    private static let maxBufferedLines = 512

    public init(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]?
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
        processOperations = .live
        trackerDidPoll = {}
        (lineStream, lineContinuation) = AsyncThrowingStream<Data, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.maxBufferedLines))
        (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
    }

    init(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]?,
        processOperations: ProcessOperations = .live,
        trackerDidPoll: @escaping @Sendable () -> Void
    ) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
        self.environment = environment
        self.processOperations = processOperations
        self.trackerDidPoll = trackerDidPoll
        (lineStream, lineContinuation) = AsyncThrowingStream<Data, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.maxBufferedLines))
        (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
    }

    /// Lines from the child's stdout. Finishes when stdout closes.
    public nonisolated var lines: AsyncThrowingStream<Data, any Error> { lineStream }

    /// Fires once with the child's exit code.
    public nonisolated var onExit: AsyncStream<Int32> { exitStream }

    public func start() throws {
        guard !started else { return }
        guard let resolved = Self.resolveExecutable(executable, environment: environment) else {
            throw TransportError.spawnFailed(
                "\(executable) was not found on PATH")
        }
        process.executableURL = resolved
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let lineContinuation = self.lineContinuation
        let drainer = StdoutDrainer(
            handle: stdoutPipe.fileHandleForReading,
            buffer: buffer,
            continuation: lineContinuation,
            maxLineBytes: Self.maxLineBytes)
        stdoutDrainer = drainer
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                drainer.finish()
                return
            }
            drainer.ingest(data)
        }

        let stderrLog = self.stderrLog
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stderrLog.append(String(decoding: data, as: UTF8.self))
        }

        let exitContinuation = self.exitContinuation
        process.terminationHandler = { proc in
            exitContinuation.yield(proc.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw TransportError.spawnFailed(error.localizedDescription)
        }
        started = true
        let pid = process.processIdentifier
        if setpgid(pid, pid) == 0 || getpgid(pid) == pid {
            processGroupID = pid
        }
        guard let leader = processOperations.snapshot(pid) else {
            kill(pid, SIGKILL)
            process.waitUntilExit()
            finishStreams(discardingPendingData: true)
            throw TransportError.spawnFailed("could not establish child process identity")
        }
        processTreeTracker = ProcessTreeTracker(
            leader: leader,
            processGroupID: processGroupID,
            operations: processOperations)
        processTreeTracker?.refresh(
            until: ContinuousClock.now.advanced(by: .milliseconds(20)))
        descendantTrackerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.recordDescendants()
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
            }
        }
    }

    public func write(_ line: Data) async throws {
        guard started else { throw TransportError.notStarted }
        guard !stdinClosed, process.isRunning else { throw TransportError.closed }
        let handle = stdinPipe.fileHandleForWriting
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writeQueue.async {
                do {
                    try handle.write(contentsOf: line)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: TransportError.closed)
                }
            }
        }
    }

    public func stderrSnapshot() -> String { stderrLog.snapshot() }

    /// Close stdin and escalate until the supplied deadline. `true` means the
    /// child is confirmed dead; callers must retain ownership on `false`.
    @discardableResult
    public func shutdown(
        deadline: ContinuousClock.Instant? = nil
    ) async -> Bool {
        guard started else { return true }
        let deadline = deadline ?? ContinuousClock.now.advanced(by: .seconds(3))
        let wasLeaderRunning = process.isRunning
        descendantTrackerTask?.cancel()
        descendantTrackerTask = nil
        recordDescendants(until: deadline)
        closeStdin()
        // The leader can exit on EOF while a descendant still holds stdout.
        // Continue through group teardown so `finishStreams()` cannot block on
        // that inherited descriptor.
        _ = await waitForExit(until: min(deadline, ContinuousClock.now.advanced(by: .seconds(1))))

        processTreeTracker?.signal(SIGTERM, until: deadline)
        _ = await waitForExit(until: min(deadline, ContinuousClock.now.advanced(by: .seconds(1))))
        processTreeTracker?.signal(SIGKILL, until: deadline)
        let exited = await waitForExit(until: deadline)
        if exited { finishStreams(discardingPendingData: wasLeaderRunning) }
        return exited
    }

    /// Foundation's `Process` needs a concrete path, so a bare name like `omp`
    /// is looked up on PATH the way a shell would.
    static func resolveExecutable(
        _ executable: String, environment: [String: String]?
    ) -> URL? {
        if executable.contains("/") {
            let url = URL(fileURLWithPath: executable)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let path = environment?["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func closeStdin() {
        guard !stdinClosed else { return }
        stdinClosed = true
        try? stdinPipe.fileHandleForWriting.close()
    }

    private func waitForExit(
        until deadline: ContinuousClock.Instant
    ) async -> Bool {
        while ContinuousClock.now < deadline {
            if hasExited(until: deadline) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return hasExited(until: deadline)
    }

    private func hasExited(until deadline: ContinuousClock.Instant) -> Bool {
        processTreeTracker?.refresh(until: deadline)
        guard !process.isRunning else { return false }
        return processTreeTracker?.isTerminated(until: deadline) ?? true
    }

    private func recordDescendants(
        until deadline: ContinuousClock.Instant = ContinuousClock.now.advanced(by: .milliseconds(10))
    ) {
        trackerDidPoll()
        processTreeTracker?.refresh(until: deadline)
    }

    private func finishStreams(discardingPendingData: Bool) {
        descendantTrackerTask?.cancel()
        descendantTrackerTask = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutDrainer?.finish(
            drainingPendingData: !discardingPendingData,
            closingHandle: discardingPendingData)
        exitContinuation.finish()
    }

}

/// Accumulates stdout bytes and splits complete lines off the front.
final class LineBuffer: @unchecked Sendable {
    private var storage = Data()
    private var failed = false
    private let lock = NSLock()

    func append(_ data: Data, maxLineBytes: Int) -> LineBufferOutput {
        lock.lock()
        defer { lock.unlock() }
        guard !failed else { return LineBufferOutput(lines: [], didOverflow: true) }
        storage.append(data)
        var lines: [Data] = []
        while let newlineIndex = storage.firstIndex(of: UInt8(ascii: "\n")) {
            var line = storage[storage.startIndex..<newlineIndex]
            storage = Data(storage[storage.index(after: newlineIndex)...])
            if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
            guard line.count <= maxLineBytes else {
                failed = true
                storage.removeAll(keepingCapacity: false)
                return LineBufferOutput(lines: lines, didOverflow: true)
            }
            if !line.isEmpty { lines.append(Data(line)) }
        }
        if storage.count > maxLineBytes {
            failed = true
            storage.removeAll(keepingCapacity: false)
            return LineBufferOutput(lines: lines, didOverflow: true)
        }
        return LineBufferOutput(lines: lines, didOverflow: false)
    }
}

struct LineBufferOutput {
    let lines: [Data]
    let didOverflow: Bool
}

/// Serializes callback reads and the final drain so stdout is consumed exactly
/// once, even when EOF and Process.terminationHandler arrive together.
private final class StdoutDrainer: @unchecked Sendable {
    private let handle: FileHandle
    private let buffer: LineBuffer
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let maxLineBytes: Int
    private let lock = NSLock()
    private var finished = false

    init(
        handle: FileHandle,
        buffer: LineBuffer,
        continuation: AsyncThrowingStream<Data, any Error>.Continuation,
        maxLineBytes: Int
    ) {
        self.handle = handle
        self.buffer = buffer
        self.continuation = continuation
        self.maxLineBytes = maxLineBytes
    }

    func ingest(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        let output = buffer.append(data, maxLineBytes: maxLineBytes)
        for line in output.lines {
            guard yield(line) else { return }
        }
        if output.didOverflow { fail(TransportError.backlogOverflow) }
    }

    func finish(
        drainingPendingData: Bool = false,
        closingHandle: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        handle.readabilityHandler = nil
        if drainingPendingData {
            // Every writer is confirmed dead before this path. Drain in bounded
            // chunks instead of collecting an unbounded readToEnd allocation.
            while true {
                let remaining = handle.availableData
                guard !remaining.isEmpty else { break }
                let output = buffer.append(remaining, maxLineBytes: maxLineBytes)
                for line in output.lines {
                    guard yield(line) else { return }
                }
                if output.didOverflow {
                    fail(TransportError.backlogOverflow)
                    return
                }
            }
        }
        if closingHandle { try? handle.close() }
        continuation.finish()
    }

    private func yield(_ line: Data) -> Bool {
        switch continuation.yield(line) {
        case .enqueued:
            return true
        case .dropped:
            fail(TransportError.backlogOverflow)
            return false
        case .terminated:
            finished = true
            handle.readabilityHandler = nil
            return false
        @unknown default:
            fail(TransportError.backlogOverflow)
            return false
        }
    }

    private func fail(_ error: any Error) {
        finished = true
        handle.readabilityHandler = nil
        try? handle.close()
        continuation.finish(throwing: error)
    }
}

/// Bounded ring of stderr chunks for diagnostics on failure.
private final class StderrLog: @unchecked Sendable {
    private var chunks: [String] = []
    private let maxChunks: Int
    private let lock = NSLock()

    init(maxChunks: Int) { self.maxChunks = maxChunks }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        chunks.append(text)
        if chunks.count > maxChunks { chunks.removeFirst(chunks.count - maxChunks) }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}
