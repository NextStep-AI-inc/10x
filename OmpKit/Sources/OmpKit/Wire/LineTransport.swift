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
    private(set) public var exitStatus: Int32?

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
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let buffer = self.buffer
        let lineContinuation = self.lineContinuation
        let maxLineBytes = Self.maxLineBytes
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                lineContinuation.finish()
                return
            }
            for line in buffer.append(data, maxLineBytes: maxLineBytes) {
                lineContinuation.yield(line)
            }
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
            lineContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw TransportError.spawnFailed(error.localizedDescription)
        }
        started = true
    }

    public func write(_ line: Data) throws {
        guard started else { throw TransportError.notStarted }
        guard !stdinClosed, process.isRunning else { throw TransportError.closed }
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: line)
        } catch {
            throw TransportError.closed
        }
    }

    public func stderrSnapshot() -> String { stderrLog.snapshot() }

    /// Close stdin, then escalate: 1 s to exit, SIGTERM, 1 s more, SIGKILL.
    public func shutdown() async {
        guard started else { return }
        closeStdin()

        if await waitForExit(timeout: .seconds(1)) { finishStreams(); return }
        if process.isRunning { process.terminate() }
        if await waitForExit(timeout: .seconds(1)) { finishStreams(); return }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
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
            if !process.isRunning {
                exitStatus = process.terminationStatus
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        if !process.isRunning {
            exitStatus = process.terminationStatus
            return true
        }
        return false
    }

    private func finishStreams() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        lineContinuation.finish()
        exitContinuation.finish()
    }
}

/// Accumulates stdout bytes and splits complete lines off the front.
private final class LineBuffer: @unchecked Sendable {
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
