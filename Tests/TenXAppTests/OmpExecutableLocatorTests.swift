import Darwin
import Foundation
import Testing
@testable import TenXApp

@Test func locatorAcceptsPreferredExecutableAndReadsItsVersion() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-locator-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appending(path: "omp")
    try "#!/bin/sh\nprintf '18.0.4\\n'\n".write(
        to: executable,
        atomically: true,
        encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)

    let installation = try await OmpExecutableLocator().locate(preferredURL: executable)

    #expect(installation == OmpInstallation(
        executableURL: executable.standardizedFileURL,
        version: "18.0.4"))
}

@Test func cancellingExecutableLookupReapsTheInspectionCommand() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "locator.pid")
    let executable = try fixture.executable(
        name: "blocked-locator",
        body: "printf '%s' $$ > '\(pidFile.path)'; trap '' TERM; while :; do sleep 1; done")
    let operation = Task {
        try await OmpExecutableLocator().locate(preferredURL: executable)
    }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 1)
    let pid = try #require(pids.first)

    operation.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    #expect(kill(pid, 0) == -1)
    #expect(errno == ESRCH)
}
