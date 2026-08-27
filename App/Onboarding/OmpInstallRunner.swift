import Darwin
import Foundation

enum OmpInstallError: Error, Equatable, Sendable {
    case failed(status: Int32)
}

/// Runs the documented OMP install command and streams its merged output.
///
/// Not `OmpCommandRunner`: that collects output with `readToEnd`, so nothing
/// appears until the process exits. A network install needs to show progress.
struct OmpInstallRunner: Sendable {
    /// The command shown to the user before it runs. Not a login shell: the
    /// installer needs nothing from rc files, and sourcing them can hang on a
    /// slow profile.
    static let command = "curl -fsSL https://omp.sh/install | sh"

    private let command: String
    private let isProcessGroupSignallingEnabled: Bool

    /// - Parameter isProcessGroupSignallingEnabled: Test seam. Foundation makes
    ///   every spawned child a process-group leader, so the descendant-walk
    ///   fallback in `ChildSignaller` is unreachable in production on macOS and
    ///   would otherwise ship with no coverage. Tests set this false to force it.
    init(
        command: String = OmpInstallRunner.command,
        isProcessGroupSignallingEnabled: Bool = true
    ) {
        self.command = command
        self.isProcessGroupSignallingEnabled = isProcessGroupSignallingEnabled
    }

    func run() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = OmpProcessEnvironment.resolved()

            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            let lines = LineAccumulator()
            let child = ChildSignaller(
                isProcessGroupSignallingEnabled: isProcessGroupSignallingEnabled)

            output.fileHandleForReading.readabilityHandler = { handle in
                for line in lines.take(handle.availableData) {
                    continuation.yield(line)
                }
            }

            process.terminationHandler = { finished in
                child.markExited()
                output.fileHandleForReading.readabilityHandler = nil
                let remainder = (try? output.fileHandleForReading.readToEnd()) ?? Data()
                for line in lines.drain(remainder) {
                    continuation.yield(line)
                }
                if finished.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(
                        throwing: OmpInstallError.failed(status: finished.terminationStatus))
                }
            }

            // Only `.cancelled` — a consumer that stopped iterating — kills the
            // install. `.finished` is this stream's own `finish()` above, by
            // which point the child is already reaped.
            //
            // Signals by pid rather than by holding the `Process`: the process
            // owns the two handlers that capture `continuation`, so reaching
            // back to it from storage-owned `onTermination` would build a loop.
            continuation.onTermination = { reason in
                guard case .cancelled = reason else { return }
                child.terminate()
            }

            do {
                try process.run()
                child.adopt(process.processIdentifier)
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                continuation.finish(throwing: error)
            }
        }
    }
}

/// Signals an abandoned install by pid, whole process group where it can.
///
/// `Process.terminate()` reaches only `/bin/sh`. The real command is
/// `curl … | sh`, whose two halves are the shell's own children, so
/// terminating the shell alone leaves the download running. Same shape as
/// `OmpCommandRunner`'s `killpg` and `LineTransport`'s `setpgid` guard.
private final class ChildSignaller: @unchecked Sendable {
    private let isProcessGroupSignallingEnabled: Bool
    private let lock = NSLock()
    private var processID: pid_t?
    private var processGroupID: pid_t?
    private var hasExited = false
    private var isTerminationRequested = false

    init(isProcessGroupSignallingEnabled: Bool = true) {
        self.isProcessGroupSignallingEnabled = isProcessGroupSignallingEnabled
    }

    /// Records the launched child and moves it into its own process group.
    ///
    /// `setpgid` from this side races the child's `exec`, so the group is
    /// claimed only once confirmed to be the child's own — signalling a group
    /// we do not own would be signalling the app itself.
    func adopt(_ pid: pid_t) {
        lock.lock()
        processID = pid
        if isProcessGroupSignallingEnabled,
           setpgid(pid, pid) == 0 || getpgid(pid) == pid {
            processGroupID = pid
        }
        // A consumer can abandon the stream between `onTermination` being set
        // and the spawn returning, which leaves nothing to signal at the time.
        let wasAbandonedBeforeLaunch = isTerminationRequested && !hasExited
        lock.unlock()
        if wasAbandonedBeforeLaunch { terminate() }
    }

    /// The child is reaped; its pid must not be signalled again.
    func markExited() {
        lock.lock()
        defer { lock.unlock() }
        hasExited = true
    }

    func terminate() {
        lock.lock()
        isTerminationRequested = true
        let target = hasExited ? nil : processID
        let group = processGroupID
        lock.unlock()

        guard let target else { return }
        if let group {
            // Descendants inherit the leader's group, so the pipeline dies whole.
            killpg(group, SIGTERM)
            return
        }

        // No group we can prove is the child's own, so signalling one would
        // risk signalling the app itself. Walk the tree instead, deepest first,
        // so `curl | sh` still dies whole. Snapshotted here rather than at
        // launch: a shell has not yet forked its pipeline when `run()` returns,
        // so an adopt-time snapshot is always empty.
        for descendant in Self.descendantPIDs(of: target).reversed() {
            kill(descendant, SIGTERM)
        }
        kill(target, SIGTERM)
    }

    /// The leader's children, depth first. Same `pgrep` walk as
    /// `LineTransport.descendantPIDs`.
    private static func descendantPIDs(of parent: pid_t) -> [pid_t] {
        let query = Process()
        let output = Pipe()
        query.executableURL = URL(filePath: "/usr/bin/pgrep")
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

/// Splits streamed bytes into lines. Written to from a Foundation callback
/// queue and from the termination handler, so it holds a lock.
private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    /// Complete lines available in `chunk` plus anything held over.
    func take(_ chunk: Data) -> [String] {
        guard !chunk.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    /// Everything left, including a final line with no trailing newline.
    func drain(_ chunk: Data) -> [String] {
        var lines = take(chunk)
        lock.lock()
        defer { lock.unlock() }
        if !buffer.isEmpty {
            lines.append(String(decoding: buffer, as: UTF8.self))
            buffer.removeAll()
        }
        return lines
    }
}
