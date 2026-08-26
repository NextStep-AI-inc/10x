import Darwin
import Foundation
import Synchronization

enum OmpCommandRunnerError: Error, Sendable {
    case nonzeroExit(Int32)
}

struct OmpCommandRunner: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> Data {
        let state = OmpCommandProcessState(
            executableURL: executableURL,
            arguments: arguments)
        let worker = Task.detached { try await state.run() }

        return try await withTaskCancellationHandler {
            let data = try await worker.value
            try Task.checkCancellation()
            return data
        } onCancel: {
            worker.cancel()
            state.cancel()
        }
    }
}

private struct OmpCommandProcessStorage {
    let process: Process
    let output: Pipe
    let error: Pipe
    var isCancellationRequested = false
    var processGroupID: pid_t?
    var cancellationDescendants: [pid_t] = []
}

private struct OmpCommandProcessTarget {
    let group: pid_t?
    let pid: pid_t
    let descendants: [pid_t]
    let isLeaderRunning: Bool
}

private final class OmpCommandProcessState: Sendable {
    private let storage: Mutex<OmpCommandProcessStorage>

    init(executableURL: URL, arguments: [String]) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        storage = Mutex(OmpCommandProcessStorage(
            process: process,
            output: output,
            error: error))
    }

    func run() async throws -> Data {
        try Task.checkCancellation()
        let started = try storage.withLock { storage in
            try storage.process.run()
            let pid = storage.process.processIdentifier
            storage.processGroupID = setpgid(pid, pid) == 0 || getpgid(pid) == pid
                ? pid
                : nil
            return (
                storage.process,
                storage.output.fileHandleForReading,
                storage.error.fileHandleForReading,
                storage.isCancellationRequested)
        }
        if started.3 { cancel() }

        async let outputData = started.1.readToEnd() ?? Data()
        async let errorData = started.2.readToEnd() ?? Data()
        started.0.waitUntilExit()
        let data = try await outputData
        _ = try await errorData
        try Task.checkCancellation()
        guard started.0.terminationStatus == 0 else {
            throw OmpCommandRunnerError.nonzeroExit(started.0.terminationStatus)
        }
        return data
    }

    func cancel() {
        let target = storage.withLock { storage -> OmpCommandProcessTarget? in
            storage.isCancellationRequested = true
            guard storage.process.isRunning else { return nil }
            return OmpCommandProcessTarget(
                group: storage.processGroupID,
                pid: storage.process.processIdentifier,
                descendants: [],
                isLeaderRunning: true)
        }
        guard let target else { return }
        let descendants = target.group == nil ? Self.descendantPIDs(of: target.pid) : []
        storage.withLock { storage in
            storage.cancellationDescendants = descendants
        }
        signal(
            target: OmpCommandProcessTarget(
                group: target.group,
                pid: target.pid,
                descendants: descendants,
                isLeaderRunning: true),
            signal: SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
            self.forceKillIfNeeded()
        }
    }

    private func forceKillIfNeeded() {
        let target = storage.withLock { storage -> OmpCommandProcessTarget? in
            guard storage.isCancellationRequested,
                  storage.process.processIdentifier > 0
            else { return nil }
            return OmpCommandProcessTarget(
                group: storage.processGroupID,
                pid: storage.process.processIdentifier,
                descendants: storage.cancellationDescendants,
                isLeaderRunning: storage.process.isRunning)
        }
        guard let target else { return }
        let descendants = target.group == nil && target.isLeaderRunning
            ? target.descendants + Self.descendantPIDs(of: target.pid)
            : target.descendants
        signal(
            target: OmpCommandProcessTarget(
                group: target.group,
                pid: target.pid,
                descendants: descendants,
                isLeaderRunning: target.isLeaderRunning),
            signal: SIGKILL)
    }

    private func signal(
        target: OmpCommandProcessTarget,
        signal: Int32
    ) {
        if let group = target.group {
            killpg(group, signal)
        } else {
            for descendant in target.descendants.reversed() { kill(descendant, signal) }
            if target.isLeaderRunning { kill(target.pid, signal) }
        }
    }

    private static func descendantPIDs(of parent: pid_t) -> [pid_t] {
        let query = Process()
        let output = Pipe()
        query.executableURL = URL(filePath: "/usr/bin/pgrep")
        query.arguments = ["-P", String(parent)]
        query.standardOutput = output
        query.standardError = FileHandle.nullDevice
        guard (try? query.run()) != nil else { return [] }
        query.waitUntilExit()
        let direct = String(
            decoding: (try? output.fileHandleForReading.readToEnd()) ?? Data(),
            as: UTF8.self)
            .split(whereSeparator: \Character.isWhitespace)
            .compactMap { pid_t($0) }
        return direct + direct.flatMap { descendantPIDs(of: $0) }
    }
}
