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

    init(command: String = OmpInstallRunner.command) {
        self.command = command
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
            let child = ChildSignaller()

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
    private let lock = NSLock()
    private var processID: pid_t?
    private var processGroupID: pid_t?
    private var hasExited = false
    private var isTerminationRequested = false

    /// Records the launched child and moves it into its own process group.
    ///
    /// `setpgid` from this side races the child's `exec`, so the group is
    /// claimed only once confirmed to be the child's own — signalling a group
    /// we do not own would be signalling the app itself.
    func adopt(_ pid: pid_t) {
        lock.lock()
        processID = pid
        if setpgid(pid, pid) == 0 || getpgid(pid) == pid {
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
            killpg(group, SIGTERM)
        } else {
            kill(target, SIGTERM)
        }
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
