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

@Test func leaseDoesNotSurviveIntoAnExecChild() async throws {
    let directory = try makeLeaseDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let lease = ComputerUseLease(directory: directory)
    try await lease.acquire(sessionID: "parent")

    let helper = try makeLeaseHelper(in: directory)
    let child = try HelperProcess(executableURL: helper, arguments: ["--pause"], expectedSignal: "ready")
    defer { child.stopIfNeeded() }
    try child.start()

    await lease.release()

    let replacement = ComputerUseLease(directory: directory)
    try await replacement.acquire(sessionID: "replacement")
    await replacement.release()
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
    #include <stdio.h>
    #include <string.h>
    #include <sys/file.h>
    #include <unistd.h>

    int main(int argc, char *argv[]) {
        if (argc == 2 && strcmp(argv[1], "--pause") == 0) {
            puts("ready");
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
