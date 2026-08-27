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

@Test func abandoningTheStreamTerminatesTheInstallProcess() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-install-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pidFile = directory.appending(path: "install.pid")

    // Reports its pid to the file *and* to stdout. The runner streams stdout,
    // so a fixture that only writes the file yields nothing, the consumer below
    // suspends on its first line forever, and the stream is never abandoned.
    // stdout comes second, so a line arriving proves the file is already there.
    let runner = OmpInstallRunner(
        command: "pid=$$; printf '%s\\n' \"$pid\" > '\(pidFile.path)'; "
            + "printf '%s\\n' \"$pid\"; while :; do sleep 1; done")

    let consumer = Task {
        for try await _ in runner.run() { break }   // take one line, then stop
    }
    _ = try? await consumer.value

    // Give the terminate a moment to land, then prove the child is gone.
    var pid: pid_t?
    for _ in 0..<50 {
        if let text = try? String(contentsOf: pidFile, encoding: .utf8),
           let parsed = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            pid = parsed
            break
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    let child = try #require(pid)
    for _ in 0..<50 where kill(child, 0) == 0 {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(kill(child, 0) == -1)
}
