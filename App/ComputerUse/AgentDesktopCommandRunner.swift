import Foundation
import Darwin
import OmpKit

protocol AgentDesktopCommandRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> AgentDesktopCommandOutput
}

struct AgentDesktopCommandOutput: Sendable, Equatable {
    let json: JSONValue
    let exitStatus: Int32
}

enum AgentDesktopCommandError: Error, Sendable, Equatable {
    case launchFailed(executable: String)
    case timedOut(executable: String)
    case failed(executable: String, exitStatus: Int32)
    case outputExceededLimit(executable: String)
    case invalidJSON(executable: String)
}

struct AgentDesktopCommandRunner: AgentDesktopCommandRunning {
    private static let outputLimit = 64 * 1024

    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> AgentDesktopCommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        let output = CommandOutputCollector(limit: Self.outputLimit)
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            output.appendStandardOutput(handle.availableData)
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            output.appendStandardError(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw AgentDesktopCommandError.launchFailed(executable: Self.sanitizedName(executable))
        }

        do {
            try await Self.awaitTermination(
                process,
                timeout: timeout,
                executable: Self.sanitizedName(executable))
        } catch {
            Self.terminate(process)
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        output.appendStandardOutput(standardOutput.fileHandleForReading.readDataToEndOfFile())
        output.appendStandardError(standardError.fileHandleForReading.readDataToEndOfFile())

        let name = Self.sanitizedName(executable)
        guard !output.exceededLimit else {
            throw AgentDesktopCommandError.outputExceededLimit(executable: name)
        }
        guard process.terminationStatus == 0 else {
            throw AgentDesktopCommandError.failed(executable: name, exitStatus: process.terminationStatus)
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: output.standardOutput),
              value.objectValue != nil || value.arrayValue != nil
        else {
            throw AgentDesktopCommandError.invalidJSON(executable: name)
        }
        return AgentDesktopCommandOutput(json: value, exitStatus: process.terminationStatus)
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
            guard process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func awaitTermination(
        _ process: Process,
        timeout: Duration,
        executable: String
    ) async throws {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                await waitForTermination(of: process)
                return true
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AgentDesktopCommandError.timedOut(executable: executable)
            }
            defer { group.cancelAll() }
            do {
                _ = try await group.next()
            } catch {
                terminate(process)
                throw error
            }
        }
    }

    private static func waitForTermination(of process: Process) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private static func sanitizedName(_ executable: URL) -> String {
        let name = executable.lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        return name.isEmpty ? "helper" : String(name.prefix(80))
    }
}

private final class CommandOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var stdout = Data()
    private var stderr = Data()
    private var didExceedLimit = false

    init(limit: Int) { self.limit = limit }

    var standardOutput: Data {
        lock.withLock { stdout }
    }

    var exceededLimit: Bool {
        lock.withLock { didExceedLimit }
    }

    func appendStandardOutput(_ data: Data) { append(data, to: .stdout) }
    func appendStandardError(_ data: Data) { append(data, to: .stderr) }

    private enum Stream { case stdout, stderr }

    private func append(_ data: Data, to stream: Stream) {
        lock.withLock {
            let currentCount = stdout.count + stderr.count
            let permittedCount = max(0, limit - currentCount)
            if data.count > permittedCount { didExceedLimit = true }
            let prefix = data.prefix(permittedCount)
            switch stream {
            case .stdout: stdout.append(prefix)
            case .stderr: stderr.append(prefix)
            }
        }
    }
}
