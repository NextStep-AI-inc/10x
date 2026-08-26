import Foundation

public enum TransportError: Error, Sendable, Equatable {
    case closed
    case spawnFailed(String)
    case notStarted
}

/// Newline-delimited byte transport over a child process's stdio.
///
/// Framing above this layer is JSON-per-line; this type only splits lines,
/// bounds the buffers, and owns process lifetime. Oversized unterminated lines
/// are dropped rather than allowed to grow without limit.
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
    private var stdoutDrainer: StdoutDrainer?
    private var stderrDrainer: StderrDrainer?

    /// Read from the process itself so a crash reports its real code, not just
    /// exits observed on the shutdown path.
    public var exitStatus: Int32? {
        guard started, !process.isRunning else { return nil }
        return process.terminationStatus
    }

    /// stdin writes block when the child stops draining the pipe, so they run
    /// off the actor to avoid wedging every other call.
    private let writeQueue = DispatchQueue(label: "sh.omp.ompkit.stdin")

    private let lineStream: AsyncStream<Data>
    private let lineContinuation: AsyncStream<Data>.Continuation
    private let exitStream: AsyncStream<Int32>
    private let exitContinuation: AsyncStream<Int32>.Continuation

    /// Guarded by `bufferLock` because the reader runs on a Foundation callback
    /// queue, outside the actor's executor.
    private let buffer = LineBuffer()
    private let stderrLog = StderrLog(maxChunks: 512)

    /// Slack over the protocol's 1 MiB physical frame cap before a line is
    /// considered runaway.
    private static let maxLineBytes = 1_048_576 + 65_536

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
        (lineStream, lineContinuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .unbounded)
        (exitStream, exitContinuation) = AsyncStream<Int32>.makeStream(
            bufferingPolicy: .unbounded)
    }

    /// Lines from the child's stdout. Finishes when stdout closes.
    public nonisolated var lines: AsyncStream<Data> { lineStream }

    /// Fires once with the child's exit code after draining output bytes that
    /// are available at direct-child exit. Inherited writers do not delay it.
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
        stdoutPipe.fileHandleForReading.readabilityHandler = { _ in
            drainer.consumeAvailableData()
        }

        let stderrLog = self.stderrLog
        let stderrDrainer = StderrDrainer(
            handle: stderrPipe.fileHandleForReading,
            log: stderrLog)
        self.stderrDrainer = stderrDrainer
        stderrPipe.fileHandleForReading.readabilityHandler = { _ in
            stderrDrainer.consumeAvailableData()
        }

        let exitContinuation = self.exitContinuation
        process.terminationHandler = { proc in
            // Exit is authoritative only after both output pipes are drained.
            // RpcClient uses this boundary for its final stderr diagnostics.
            drainer.finish()
            stderrDrainer.finish()
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

    /// Close stdin, then escalate: 1 s to exit, SIGTERM, 1 s more, SIGKILL.
    public func shutdown() async {
        guard started else { return }
        // Capture descendants while the leader still owns them. Foundation's
        // Process does not guarantee a fresh process group on every launch, so
        // this is the fallback when setpgid raced with exec.
        let descendants = processGroupID == nil
            ? Self.descendantPIDs(of: process.processIdentifier) : []
        closeStdin()
        _ = await waitForExit(timeout: .seconds(1))

        if let processGroupID {
            killpg(processGroupID, SIGTERM)
        } else {
            for pid in descendants.reversed() { kill(pid, SIGTERM) }
            if process.isRunning { process.terminate() }
        }
        _ = await waitForExit(timeout: .seconds(1))
        if let processGroupID {
            killpg(processGroupID, SIGKILL)
        } else {
            for pid in descendants.reversed() { kill(pid, SIGKILL) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        _ = await waitForExit(timeout: .seconds(1))
        finishStreams()
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

    private func waitForExit(timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !process.isRunning { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return !process.isRunning
    }

    private func finishStreams() {
        stderrDrainer?.finish()
        stdoutDrainer?.finish()
        exitContinuation.finish()
    }

    private static func descendantPIDs(of parent: pid_t) -> [pid_t] {
        let query = Process()
        let output = Pipe()
        query.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        query.arguments = ["-P", String(parent)]
        query.standardOutput = output
        query.standardError = FileHandle.nullDevice
        guard (try? query.run()) != nil else { return [] }
        query.waitUntilExit()
        let text = String(
            decoding: (try? output.fileHandleForReading.readToEnd()) ?? Data(),
            as: UTF8.self)
        let direct = text.split(whereSeparator: \Character.isWhitespace)
            .compactMap { pid_t($0) }
        return direct + direct.flatMap { descendantPIDs(of: $0) }
    }
}

/// Serializes stderr callback reads with the final process-exit drain so the
/// exit event cannot overtake crash diagnostics still buffered in the pipe.
private final class StderrDrainer: @unchecked Sendable {
    private let handle: FileHandle
    private let log: StderrLog
    private let lock = NSLock()
    private var finished = false

    init(handle: FileHandle, log: StderrLog) {
        self.handle = handle
        self.log = log
    }

    func consumeAvailableData() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        let data = handle.availableData
        if data.isEmpty {
            finished = true
            handle.readabilityHandler = nil
            return
        }
        log.append(String(decoding: data, as: UTF8.self))
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        handle.readabilityHandler = nil
        let remaining = readCurrentlyAvailable(from: handle.fileDescriptor)
        if !remaining.isEmpty {
            log.append(String(decoding: remaining, as: UTF8.self))
        }
    }
}

private func readCurrentlyAvailable(from descriptor: Int32) -> Data {
    let originalFlags = fcntl(descriptor, F_GETFL)
    guard originalFlags >= 0,
          fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
        return Data()
    }
    defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let bytesRead = buffer.withUnsafeMutableBytes { bytes in
            read(descriptor, bytes.baseAddress, bytes.count)
        }
        if bytesRead > 0 {
            result.append(contentsOf: buffer[..<bytesRead])
            continue
        }
        if bytesRead < 0, errno == EINTR { continue }
        // EOF and EAGAIN both end the direct-child snapshot. Waiting for a
        // descendant's inherited writer would make process exit unbounded.
        return result
    }
}

/// Accumulates stdout bytes and splits complete lines off the front.
final class LineBuffer: @unchecked Sendable {
    private var storage = Data()
    private var overflowing = false
    private let lock = NSLock()

    func append(_ data: Data, maxLineBytes: Int) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        storage.append(data)
        var lines: [Data] = []
        while let newlineIndex = storage.firstIndex(of: UInt8(ascii: "\n")) {
            var line = storage[storage.startIndex..<newlineIndex]
            storage = Data(storage[storage.index(after: newlineIndex)...])
            if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
            if overflowing {
                // Tail of a discarded runaway line; drop it and resync.
                overflowing = false
                continue
            }
            if !line.isEmpty { lines.append(Data(line)) }
        }
        if storage.count > maxLineBytes {
            // No newline in sight and past the cap: drop and wait for a resync.
            storage.removeAll(keepingCapacity: false)
            overflowing = true
        }
        return lines
    }
}

/// Serializes callback reads and the final drain so stdout is consumed exactly
/// once, even when EOF and Process.terminationHandler arrive together.
private final class StdoutDrainer: @unchecked Sendable {
    private let handle: FileHandle
    private let buffer: LineBuffer
    private let continuation: AsyncStream<Data>.Continuation
    private let maxLineBytes: Int
    private let lock = NSLock()
    private var finished = false

    init(
        handle: FileHandle,
        buffer: LineBuffer,
        continuation: AsyncStream<Data>.Continuation,
        maxLineBytes: Int
    ) {
        self.handle = handle
        self.buffer = buffer
        self.continuation = continuation
        self.maxLineBytes = maxLineBytes
    }

    func consumeAvailableData() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        let data = handle.availableData
        if data.isEmpty {
            finished = true
            handle.readabilityHandler = nil
            continuation.finish()
            return
        }
        for line in buffer.append(data, maxLineBytes: maxLineBytes) {
            continuation.yield(line)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        handle.readabilityHandler = nil
        let remaining = readCurrentlyAvailable(from: handle.fileDescriptor)
        if !remaining.isEmpty {
            for line in buffer.append(remaining, maxLineBytes: maxLineBytes) {
                continuation.yield(line)
            }
        }
        continuation.finish()
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
