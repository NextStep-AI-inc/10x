import Foundation
import Testing
@testable import TenXApp

private func collect(
    _ runner: OmpInstallRunner
) async throws -> [String] {
    var lines: [String] = []
    for try await line in runner.run() { lines.append(line) }
    return lines
}

@Test func installRunnerStreamsMergedOutputLineByLine() async throws {
    let runner = OmpInstallRunner(
        command: "printf 'first\\nsecond\\n'; printf 'third\\n' 1>&2")

    let lines = try await collect(runner)

    #expect(lines.contains("first"))
    #expect(lines.contains("second"))
    #expect(lines.contains("third"))
}

@Test func installRunnerReportsANonzeroExitAfterDeliveringItsOutput() async throws {
    let runner = OmpInstallRunner(command: "printf 'why it failed\\n'; exit 3")

    var lines: [String] = []
    var thrown: Error?
    do {
        for try await line in runner.run() { lines.append(line) }
    } catch {
        thrown = error
    }

    #expect(lines == ["why it failed"])
    #expect(thrown as? OmpInstallError == .failed(status: 3))
}

@Test func installRunnerEmitsAFinalLineThatHasNoTrailingNewline() async throws {
    let runner = OmpInstallRunner(command: "printf 'no trailing newline'")

    let lines = try await collect(runner)

    #expect(lines == ["no trailing newline"])
}

/// Reproduces the race between the pipe's readability-handler callback and
/// `process.terminationHandler`: the callback can still be mid-flight,
/// between reading `availableData` and yielding it, when the process exit
/// fires on a different thread and finishes the stream first. Any yields
/// still in flight at that point are silently dropped.
///
/// Two things widen the race window past luck rather than adding blind
/// trials: a multi-line fixture (30 lines makes losing the yield loop
/// partway through detectable as a truncated array, not just an empty one)
/// and genuine concurrency — many install runs racing at once, the same
/// contention that surfaced the bug under a full parallel suite run.
private let manyLinesThenFailure =
    "for n in $(seq 1 30); do printf 'line %d\\n' \"$n\"; done; exit 3"

@Test func installRunnerDeliversAllOutputBeforeAConcurrentNonzeroExit() async throws {
    let expectedLines = (1...30).map { "line \($0)" }

    try await withThrowingTaskGroup(of: (lines: [String], thrown: Error?).self) { group in
        for _ in 0..<24 {
            group.addTask {
                let runner = OmpInstallRunner(command: manyLinesThenFailure)
                var lines: [String] = []
                var thrown: Error?
                do {
                    for try await line in runner.run() { lines.append(line) }
                } catch {
                    thrown = error
                }
                return (lines, thrown)
            }
        }
        for try await result in group {
            #expect(result.lines == expectedLines)
            #expect(result.thrown as? OmpInstallError == .failed(status: 3))
        }
    }
}

/// A fixture that reports its own pid and a backgrounded descendant's pid, both
/// to `pidFile` and to stdout. The runner streams stdout, so a fixture that only
/// writes the file yields nothing and a consumer waiting for its first line hangs
/// instead of ever abandoning the stream. stdout comes second, so a line arriving
/// proves the file is already on disk.
private func reportingFixture(pidFile: URL) -> String {
    "sleep 300 & descendant=$!; leader=$$; "
        + "printf '%s\n%s\n' \"$leader\" \"$descendant\" > '\(pidFile.path)'; "
        + "printf '%s\n%s\n' \"$leader\" \"$descendant\"; "
        + "while :; do sleep 1; done"
}

/// The leader and descendant pids the fixture reported, once both are on disk.
private func reportedPIDs(in pidFile: URL) async throws -> (leader: pid_t, descendant: pid_t) {
    for _ in 0..<100 {
        let text = (try? String(contentsOf: pidFile, encoding: .utf8)) ?? ""
        let pids = text.split(whereSeparator: \Character.isNewline)
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
        if pids.count == 2 { return (pids[0], pids[1]) }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw FixtureError.pidsNeverReported
}

private enum FixtureError: Error { case pidsNeverReported }

/// Polls up to one second for `pid` to disappear.
private func waitForExit(of pid: pid_t) async throws {
    for _ in 0..<50 where kill(pid, 0) == 0 {
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// Consumes one line, then stops — abandoning the stream.
private func takeOneLineThenAbandon(_ runner: OmpInstallRunner) async {
    let consumer = Task {
        for try await _ in runner.run() { break }
    }
    _ = try? await consumer.value
}

@Test func abandoningTheStreamTerminatesTheInstallProcess() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pidFile = directory.appending(path: "install.pid")

    let runner = OmpInstallRunner(command: reportingFixture(pidFile: pidFile))

    await takeOneLineThenAbandon(runner)

    let (leader, descendant) = try await reportedPIDs(in: pidFile)
    try await waitForExit(of: leader)
    try await waitForExit(of: descendant)

    #expect(kill(leader, 0) == -1)
    // The real command is `curl ... | sh`, whose halves are the shell's own
    // children. Killing the leader alone would leave the download running.
    #expect(kill(descendant, 0) == -1)
}

/// Foundation makes every spawned child a process-group leader, so `killpg`
/// carries the descendants and the `processGroupID == nil` branch never runs in
/// production on macOS. Disabling the group signalling is the only way to reach
/// the descendant walk, which otherwise ships untested.
@Test func abandoningTheStreamTerminatesDescendantsWithoutAProcessGroup() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pidFile = directory.appending(path: "install.pid")

    let runner = OmpInstallRunner(
        command: reportingFixture(pidFile: pidFile),
        isProcessGroupSignallingEnabled: false)

    await takeOneLineThenAbandon(runner)

    let (leader, descendant) = try await reportedPIDs(in: pidFile)
    try await waitForExit(of: leader)
    try await waitForExit(of: descendant)

    #expect(kill(leader, 0) == -1)
    #expect(kill(descendant, 0) == -1)
}
