import Darwin
import Foundation
import Testing
@testable import TenXApp

@Test func ompCommandRunnerReturnsStdoutWithoutExposingStderr() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let executable = try fixture.executable(
        name: "success",
        body: "printf 'ready\\n'; printf 'token=secret\\n' >&2")

    let data = try await OmpCommandRunner().run(
        executableURL: executable,
        arguments: [])

    #expect(String(decoding: data, as: UTF8.self) == "ready\n")
    #expect(!String(decoding: data, as: UTF8.self).contains("secret"))
}

@Test func ompCommandRunnerPreservesTheInheritedEnvironment() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let executable = try fixture.executable(
        name: "environment",
        body: "test -n \"$PATH\" || exit 9; printf 'inherited\\n'")

    let data = try await OmpCommandRunner().run(
        executableURL: executable,
        arguments: [])

    #expect(String(decoding: data, as: UTF8.self) == "inherited\n")
}

@Test func ompCommandRunnerReportsTypedNonzeroExit() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let executable = try fixture.executable(name: "failure", body: "exit 7")

    do {
        _ = try await OmpCommandRunner().run(
            executableURL: executable,
            arguments: [])
        Issue.record("Expected a typed nonzero exit")
    } catch OmpCommandRunnerError.nonzeroExit(let status) {
        #expect(status == 7)
    } catch {
        Issue.record("Expected nonzeroExit(7), got \(error)")
    }
}

@Test func cancellingOmpCommandRunnerReapsAnIgnoringProcessGroup() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "blocked.pid")
    let executable = try fixture.executable(
        name: "blocked",
        body: "trap '' TERM; /bin/sh -c 'trap \"\" TERM; while :; do sleep 1; done' & child=$!; printf '%s %s' $$ $child > \"$1\"; wait $child")
    let operation = Task {
        try await OmpCommandRunner().run(
            executableURL: executable,
            arguments: [pidFile.path])
    }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 2)

    operation.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

@Test func cancellationEscalatesAfterTheProcessLeaderExits() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "exited-leader.pid")
    let executable = try fixture.executable(
        name: "exited-leader",
        body: "/bin/sh -c 'trap \"\" TERM; while :; do sleep 1; done' </dev/null >/dev/null 2>&1 & child=$!; printf '%s %s' $$ $child > \"$1\"; wait $child")
    let operation = Task {
        try await OmpCommandRunner().run(
            executableURL: executable,
            arguments: [pidFile.path])
    }
    let pids = try await fixture.waitForPIDs(in: pidFile, count: 2)
    defer { for pid in pids { kill(pid, SIGKILL) } }

    operation.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

@Test func cancellationReapsADescendantSpawnedByTheTerminationHandler() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "late-descendant.pid")
    let executable = try fixture.executable(
        name: "late-descendant",
        body: """
        if [ "$1" = child ]; then trap '' TERM; while :; do sleep 1; done; fi
        pid_file="$1"
        trap '"$0" child </dev/null >/dev/null 2>&1 & printf " %s" $! >> "$pid_file"; exit 0' TERM
        printf '%s' $$ > "$pid_file"
        while :; do sleep 1; done
        """)
    let operation = Task {
        try await OmpCommandRunner().run(
            executableURL: executable,
            arguments: [pidFile.path])
    }
    var pids = try await fixture.waitForPIDs(in: pidFile, count: 1)
    defer { for pid in pids { kill(pid, SIGKILL) } }

    operation.cancel()
    pids = try await fixture.waitForPIDs(in: pidFile, count: 2)
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

enum OmpCommandFixtureError: Error {
    case timedOutWaitingForPIDs(file: URL, expectedCount: Int, observedContents: String?)
}

struct OmpCommandFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "tenx-omp-command-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func executable(name: String, body: String) throws -> URL {
        let url = root.appending(path: name)
        try ("#!/bin/sh\n" + body + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path)
        return url
    }

    func waitForPIDs(in file: URL, count: Int) async throws -> [pid_t] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var observedContents: String?
        while ContinuousClock.now < deadline {
            if let data = try? Data(contentsOf: file) {
                let contents = String(decoding: data, as: UTF8.self)
                observedContents = contents
                let pids = contents
                    .split(whereSeparator: \Character.isWhitespace)
                    .compactMap { pid_t($0) }
                if pids.count == count, pids.allSatisfy({ $0 > 0 }) {
                    return pids
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw OmpCommandFixtureError.timedOutWaitingForPIDs(
            file: file,
            expectedCount: count,
            observedContents: observedContents)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
