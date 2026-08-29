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

@Test func nonzeroExitReapsDescendantBeforeDrainingInheritedPipes() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let pidFile = fixture.root.appending(path: "nonzero-descendant.pid")
    let executable = try fixture.executable(
        name: "nonzero-descendant",
        body: """
        if [ "$1" = child ]; then trap '' TERM; while :; do sleep 1; done; fi
        pid_file="$1"
        "$0" child &
        child=$!
        printf '%s %s' $$ $child > "$pid_file"
        exit 7
        """)

    let resultBox = OmpCommandResultBox()
    let operation = Task {
        do {
            let data = try await OmpCommandRunner().run(
                executableURL: executable,
                arguments: [pidFile.path])
            await resultBox.store(.success(data))
        } catch {
            await resultBox.store(.failure(error))
        }
    }
    let pids = try await fixture.waitForPIDs(
        in: pidFile, count: 2, cancelling: operation)
    defer { for pid in pids { kill(pid, SIGKILL) } }

    // The runner needs its 500ms SIGTERM grace plus a reap before it can
    // return, so a 2s budget leaves nothing for a loaded machine. This still
    // fails a runner that drains the pipes first — it just waits like
    // waitForPIDs does rather than racing the escalation.
    let result = await fixture.waitForResult(resultBox, within: .seconds(10))
    guard let result else {
        operation.cancel()
        killpg(pids[0], SIGKILL)
        _ = await operation.result
        Issue.record("Expected nonzero exit to terminate descendants before draining inherited pipes")
        return
    }

    do {
        _ = try result.get()
        Issue.record("Expected a typed nonzero exit")
    } catch OmpCommandRunnerError.nonzeroExit(let status) {
        #expect(status == 7)
    } catch {
        Issue.record("Expected nonzeroExit(7), got \(error)")
    }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
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
    let pids = try await fixture.waitForPIDs(
        in: pidFile, count: 2, cancelling: operation)

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
    let pids = try await fixture.waitForPIDs(
        in: pidFile, count: 2, cancelling: operation)
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
        # Blocks in `wait`, which a trapped signal interrupts at once. A
        # `sleep` loop would instead fork a fresh sleep that can miss the
        # process-group SIGTERM, deferring this trap by a whole second — past
        # the runner's 500ms escalation to SIGKILL, so no descendant is ever
        # spawned and the test times out waiting for its pid.
        sleep 2147483647 &
        printf '%s' $$ > "$pid_file"
        wait
        """)
    let operation = Task {
        try await OmpCommandRunner().run(
            executableURL: executable,
            arguments: [pidFile.path])
    }
    var pids = try await fixture.waitForPIDs(
        in: pidFile, count: 1, cancelling: operation)
    defer { for pid in pids { kill(pid, SIGKILL) } }

    operation.cancel()
    pids = try await fixture.waitForPIDs(
        in: pidFile, count: 2, cancelling: operation)
    await #expect(throws: CancellationError.self) {
        _ = try await operation.value
    }

    for pid in pids {
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}

@Test func pidWaitCancelsAndAwaitsItsOperationOnTimeout() async throws {
    let fixture = try OmpCommandFixture()
    defer { fixture.cleanup() }
    let completion = CancellationCompletionProbe()
    let operation = Task {
        do {
            try await ContinuousClock().sleep(for: .seconds(60))
        } catch {
            await Task.detached {
                try? await ContinuousClock().sleep(for: .milliseconds(200))
            }.value
            await completion.finish()
            throw error
        }
    }

    await #expect(throws: OmpCommandFixtureError.self) {
        _ = try await fixture.waitForPIDs(
            in: fixture.root.appending(path: "never-created.pid"),
            count: 1,
            timeout: .milliseconds(20),
            cancelling: operation)
    }
    #expect(operation.isCancelled)
    #expect(await completion.isFinished)
}

enum OmpCommandFixtureError: Error {
    case timedOutWaitingForPIDs(file: URL, expectedCount: Int, observedContents: String?)
}

actor OmpCommandResultBox {
    private var storedResult: Result<Data, any Error>?

    func store(_ result: Result<Data, any Error>) {
        storedResult = result
    }

    func result() -> Result<Data, any Error>? {
        storedResult
    }
}

private actor CancellationCompletionProbe {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
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

    func waitForPIDs(
        in file: URL,
        count: Int,
        timeout: Duration = .seconds(10)
    ) async throws -> [pid_t] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
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

    func waitForPIDs<Success, Failure: Error>(
        in file: URL,
        count: Int,
        timeout: Duration = .seconds(10),
        cancelling operation: Task<Success, Failure>
    ) async throws -> [pid_t] {
        do {
            return try await waitForPIDs(in: file, count: count, timeout: timeout)
        } catch {
            operation.cancel()
            _ = await operation.result
            throw error
        }
    }

    func waitForResult(
        _ resultBox: OmpCommandResultBox,
        within timeout: Duration
    ) async -> Result<Data, any Error>? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let result = await resultBox.result() {
                return result
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
