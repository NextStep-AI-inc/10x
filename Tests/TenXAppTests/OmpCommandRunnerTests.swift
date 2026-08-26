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
    for pid in pids { try await fixture.waitUntilProcessIsGone(pid) }

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
    for pid in pids { try await fixture.waitUntilProcessIsGone(pid) }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

enum OmpCommandFixtureError: Error {
    case timedOutWaitingForPIDs
    case timedOutWaitingForProcess(pid_t)
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
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if let data = try? Data(contentsOf: file) {
                let pids = String(decoding: data, as: UTF8.self)
                    .split(whereSeparator: \Character.isWhitespace)
                    .compactMap { pid_t($0) }
                if pids.count == count, pids.allSatisfy({ $0 > 0 }) {
                    return pids
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw OmpCommandFixtureError.timedOutWaitingForPIDs
    }

    func waitUntilProcessIsGone(_ pid: pid_t) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if kill(pid, 0) == -1, errno == ESRCH {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw OmpCommandFixtureError.timedOutWaitingForProcess(pid)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
