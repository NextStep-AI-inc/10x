import Darwin
import Dispatch
import Foundation
import Testing
@testable import TenXApp

@Test func onlyOneLeaseOwnerCanHoldTheComputer() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = ComputerUseLease(directory: directory)
    let second = ComputerUseLease(directory: directory)

    try await first.acquire(sessionID: "session-a")
    await #expect(throws: ComputerUseLeaseError.self) {
        try await second.acquire(sessionID: "session-b")
    }

    await first.release()
    try await second.acquire(sessionID: "session-b")
    await second.release()
}

@Test func leaseIsReleasedWhenTheOwningProcessIsKilled() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let helper = try makeLeaseHelper(in: directory)
    let process = try HelperProcess(
        executableURL: helper,
        arguments: [directory.appending(path: "computer-use.lock").path],
        expectedSignal: "locked")
    defer { process.stopIfNeeded() }
    try process.start()

    let lease = ComputerUseLease(directory: directory)
    await #expect(throws: ComputerUseLeaseError.self) {
        try await lease.acquire(sessionID: "session-a")
    }

    try process.killAndWait()
    try await lease.acquire(sessionID: "session-b")
    await lease.release()
}

@Test func leaseClosesItsDescriptorWhenTheActorIsReleased() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    try await acquireLeaseAndDiscardIt(in: directory)

    let replacement = ComputerUseLease(directory: directory)
    try await replacement.acquire(sessionID: "replacement")
    await replacement.release()
}

@Test func leaseDescriptorDoesNotSurviveOwnerExitWithAnExecChild() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let helper = try makeLeaseHelper(in: directory)
    let owner = try makeLeaseOwner(in: directory)
    let process = try LeaseOwnerProcess(
        executableURL: owner,
        arguments: [directory.path, helper.path],
        traceURL: directory.appending(path: "owner-trace"))
    defer { process.stopOwnerIfNeeded() }
    let childProcessID = try process.startAndWaitForOwnerExit()
    defer { process.stopChildIfNeeded(childProcessID) }

    #expect(kill(childProcessID, 0) == 0)

    let contender = ComputerUseLease(directory: directory)
    try await contender.acquire(sessionID: "contender")
    await contender.release()

    try process.stopChild(childProcessID)
}

@Test func leaseRepairsPermissionsOnExistingPaths() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let lockURL = directory.appending(path: "computer-use.lock")
    FileManager.default.createFile(atPath: lockURL.path, contents: Data())
    try setPermissions(0o777, at: directory)
    try setPermissions(0o666, at: lockURL)

    let lease = ComputerUseLease(directory: directory)
    try await lease.acquire(sessionID: "session")
    await lease.release()

    #expect(try permissions(at: directory) == 0o700)
    #expect(try permissions(at: lockURL) == 0o600)
}

@Test func leaseRejectsASymlinkedLockPath() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let target = directory.appending(path: "target")
    try Data().write(to: target)
    let lockURL = directory.appending(path: "computer-use.lock")
    try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: target)

    let lease = ComputerUseLease(directory: directory)
    await #expect(throws: ComputerUseLeaseError.self) {
        try await lease.acquire(sessionID: "session")
    }
}

@Test func leaseMetadataSanitizesSessionDiagnostics() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let lease = ComputerUseLease(directory: directory)
    try await lease.acquire(sessionID: "session\nwith/control characters")
    await lease.release()

    let metadataURL = directory.appending(path: "computer-use.lock")
    let metadata = try String(contentsOf: metadataURL, encoding: .utf8)
    #expect(!metadata.contains("\nwith/control"))
}

private func acquireLeaseAndDiscardIt(in directory: URL) async throws {
    let lease = ComputerUseLease(directory: directory)
    try await lease.acquire(sessionID: "discarded")
}

private func makeLeaseDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-computer-use-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeLeaseHelper(in directory: URL) throws -> URL {
    let source = directory.appending(path: "lease-helper.c")
    let executable = directory.appending(path: "lease-helper")
    try """
    #include <fcntl.h>
    #include <signal.h>
    #include <stdio.h>
    #include <string.h>
    #include <sys/file.h>
    #include <unistd.h>

    static void stop_child(int signal) {
        puts("child-stopped");
        fflush(stdout);
        _exit(0);
    }

    int main(int argc, char *argv[]) {
        if (argc == 2 && strcmp(argv[1], "--pause") == 0) {
            signal(SIGTERM, stop_child);
            puts("child-ready");
            fflush(stdout);
            pause();
            return 0;
        }
        if (argc != 2) return 2;
        int descriptor = open(argv[1], O_CREAT | O_RDWR, 0600);
        if (descriptor < 0 || flock(descriptor, LOCK_EX | LOCK_NB) != 0) return 3;
        puts("locked");
        fflush(stdout);
        pause();
        return 0;
    }
    """.write(to: source, atomically: true, encoding: .utf8)

    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
    compiler.arguments = ["clang", source.path, "-o", executable.path]
    try runAndWaitForSuccess(compiler)
    return executable
}

private func makeLeaseOwner(in directory: URL) throws -> URL {
    let source = directory.appending(path: "lease-owner.swift")
    let executable = directory.appending(path: "lease-owner")
    try """
    import Darwin
    import Foundation

    @main
    struct LeaseOwner {
        static func main() async {
            let arguments = CommandLine.arguments
            let traceURL = URL(filePath: arguments[1]).appending(path: "owner-trace")
            func trace(_ message: String) {
                try? message.write(to: traceURL, atomically: true, encoding: .utf8)
            }
            trace("started")
            let lease = ComputerUseLease(directory: URL(filePath: arguments[1]))
            do {
                try await lease.acquire(sessionID: "owner")
                trace("acquired")
                var childProcessID: pid_t = 0
                let spawnResult = arguments[2].withCString { executable in
                    "--pause".withCString { pause in
                        var childArguments: [UnsafeMutablePointer<CChar>?] = [
                            UnsafeMutablePointer(mutating: executable),
                            UnsafeMutablePointer(mutating: pause),
                            nil,
                        ]
                        return posix_spawn(
                            &childProcessID,
                            executable,
                            nil,
                            nil,
                            &childArguments,
                            environ)
                    }
                }
                guard spawnResult == 0 else {
                    _exit(1)
                }
                trace("child-pid:\\(childProcessID)")
                _exit(0)
            } catch {
                trace("error")
                _exit(1)
            }
        }
    }
    """.write(to: source, atomically: true, encoding: .utf8)

    let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
    compiler.arguments = [
        "swiftc",
        "-swift-version", "6",
        root.appending(path: "App/ComputerUse/ComputerUseLease.swift").path,
        source.path,
        "-o", executable.path,
    ]
    try runAndWaitForSuccess(compiler)
    return executable
}

private func setPermissions(_ permissions: mode_t, at url: URL) throws {
    guard chmod(url.path, permissions) == 0 else {
        throw LeaseTestError.permissionChangeFailed
    }
}

private func permissions(at url: URL) throws -> mode_t {
    var information = stat()
    guard lstat(url.path, &information) == 0 else {
        throw LeaseTestError.statFailed
    }
    return information.st_mode & 0o777
}

private func runAndWaitForSuccess(_ process: Process) throws {
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    try process.run()
    guard exited.wait(timeout: .now() + 5) == .success else {
        stopProcess(process, exited: exited)
        throw LeaseTestError.processTimedOut
    }
    guard process.terminationStatus == 0 else {
        throw LeaseTestError.processFailed
    }
}

private func stopProcess(_ process: Process, exited: DispatchSemaphore) {
    guard process.isRunning else {
        return
    }
    process.terminate()
    if exited.wait(timeout: .now() + 1) == .timedOut {
        _ = kill(process.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 1)
    }
}

private final class HelperProcess {
    private let process = Process()
    private let output = Pipe()
    private let exited = DispatchSemaphore(value: 0)
    private let ready = DispatchSemaphore(value: 0)
    private let expectedSignal: String
    private let signal = ProcessSignal()

    init(executableURL: URL, arguments: [String], expectedSignal: String) throws {
        self.expectedSignal = expectedSignal
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { [exited] _ in exited.signal() }
        output.fileHandleForReading.readabilityHandler = { [ready, signal] handle in
            signal.set(String(decoding: handle.availableData, as: UTF8.self))
            ready.signal()
        }
    }

    func start() throws {
        try process.run()
        guard ready.wait(timeout: .now() + 5) == .success else {
            stopIfNeeded()
            throw LeaseTestError.processTimedOut
        }
        output.fileHandleForReading.readabilityHandler = nil
        guard signal.value.trimmingCharacters(in: .whitespacesAndNewlines) == expectedSignal else {
            stopIfNeeded()
            throw LeaseTestError.processFailed
        }
    }

    func killAndWait() throws {
        guard process.isRunning else {
            throw LeaseTestError.processFailed
        }
        guard kill(process.processIdentifier, SIGKILL) == 0 else {
            throw LeaseTestError.processFailed
        }
        guard exited.wait(timeout: .now() + 5) == .success else {
            throw LeaseTestError.processTimedOut
        }
    }

    func stopIfNeeded() {
        stopProcess(process, exited: exited)
    }
}

private final class LeaseOwnerProcess {
    private let process = Process()
    private let exited = DispatchSemaphore(value: 0)
    private let traceURL: URL

    init(executableURL: URL, arguments: [String], traceURL: URL) throws {
        self.traceURL = traceURL
        process.executableURL = executableURL
        process.arguments = arguments
        process.terminationHandler = { [exited] _ in exited.signal() }
    }

    func startAndWaitForOwnerExit() throws -> pid_t {
        try process.run()
        guard exited.wait(timeout: .now() + 5) == .success, process.terminationStatus == 0 else {
            throw LeaseTestError.processFailed
        }
        let trace = try String(contentsOf: traceURL, encoding: .utf8)
        guard let childProcessID = childProcessID(from: trace) else {
            throw LeaseTestError.processFailed
        }
        return childProcessID
    }

    func stopOwnerIfNeeded() {
        stopProcess(process, exited: exited)
    }

    func stopChild(_ childProcessID: pid_t) throws {
        guard kill(childProcessID, 0) == 0 else {
            return
        }
        let exited = DispatchSemaphore(value: 0)
        let exitSource = DispatchSource.makeProcessSource(
            identifier: childProcessID,
            eventMask: .exit,
            queue: .global())
        exitSource.setEventHandler { exited.signal() }
        exitSource.resume()
        defer { exitSource.cancel() }
        guard kill(childProcessID, SIGTERM) == 0 else {
            throw LeaseTestError.processFailed
        }
        guard exited.wait(timeout: .now() + 5) == .success else {
            _ = kill(childProcessID, SIGKILL)
            guard exited.wait(timeout: .now() + 1) == .success else {
                throw LeaseTestError.processTimedOut
            }
            return
        }
    }

    func stopChildIfNeeded(_ childProcessID: pid_t) {
        try? stopChild(childProcessID)
    }

    private func childProcessID(from output: String) -> pid_t? {
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("child-pid:") }) else {
            return nil
        }
        return Int32(line.dropFirst("child-pid:".count))
    }
}

private final class ProcessSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.withLock { storage }
    }

    func set(_ value: String) {
        lock.withLock { storage = value }
    }

}

private enum LeaseTestError: Error {
    case permissionChangeFailed
    case statFailed
    case processFailed
    case processTimedOut
}
