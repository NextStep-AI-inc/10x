import Darwin
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

    let helper = try makeLockHoldingHelper(in: directory)
    let output = Pipe()
    let process = Process()
    process.executableURL = helper
    process.arguments = [directory.appending(path: "computer-use.lock").path]
    process.standardOutput = output
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    let signal = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
    #expect(signal.trimmingCharacters(in: .whitespacesAndNewlines) == "locked")

    let lease = ComputerUseLease(directory: directory)
    await #expect(throws: ComputerUseLeaseError.self) {
        try await lease.acquire(sessionID: "session-a")
    }

    _ = kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()

    try await lease.acquire(sessionID: "session-b")
    await lease.release()
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

private func makeLeaseDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-computer-use-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeLockHoldingHelper(in directory: URL) throws -> URL {
    let source = directory.appending(path: "lock-holder.c")
    let executable = directory.appending(path: "lock-holder")
    try """
    #include <fcntl.h>
    #include <stdio.h>
    #include <sys/file.h>
    #include <unistd.h>

    int main(int argc, char *argv[]) {
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
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else {
        throw LockHoldingHelperError.compilationFailed
    }
    return executable
}

private enum LockHoldingHelperError: Error {
    case compilationFailed
}
