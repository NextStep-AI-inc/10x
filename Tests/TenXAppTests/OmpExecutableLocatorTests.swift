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

    let location = try await OmpExecutableLocator().locate(preferredURL: executable)

    #expect(location == .found(OmpInstallation(
        executableURL: executable.standardizedFileURL,
        version: "18.0.4")))
}

@Test func anExecutableThatCannotRunIsReportedSeparatelyFromAMissingOne() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    // Stands in for `#!/usr/bin/env bun` failing to find its interpreter: the
    // file is present and executable, it just cannot run.
    let executable = try fixture.executable(name: "omp", body: "exit 127")

    let locator = OmpExecutableLocator(homeDirectory: fixture.root, path: "")
    let location = try await locator.locate(preferredURL: executable)

    #expect(location == .unrunnable(executable.standardizedFileURL))
}

@Test func nothingOnDiskIsReportedAsNotFound() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let missing = fixture.root.appending(path: "absent-omp")

    let locator = OmpExecutableLocator(homeDirectory: fixture.root, path: "")
    let location = try await locator.locate(preferredURL: missing)

    #expect(location == .notFound)
}

@Test func aWorkingExecutableWinsOverABrokenOneCheckedFirst() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let broken = try fixture.executable(name: "omp", body: "exit 127")

    let directory = fixture.root.appending(path: "working", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let working = directory.appending(path: "omp")
    try "#!/bin/sh\nprintf '18.0.4\\n'\n".write(to: working, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: working.path)

    let locator = OmpExecutableLocator(homeDirectory: fixture.root, path: directory.path)
    let location = try await locator.locate(preferredURL: broken)

    #expect(location == .found(OmpInstallation(
        executableURL: working.standardizedFileURL,
        version: "18.0.4")))
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
