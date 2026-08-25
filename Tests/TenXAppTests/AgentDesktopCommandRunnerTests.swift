import Foundation
import Testing
@testable import TenXApp

@Test func commandRunnerPassesArgumentsWithoutInvokingAShell() async throws {
    let fixture = try makeArgumentPrinterFixture()
    defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }

    let output = try await AgentDesktopCommandRunner().run(
        executable: fixture,
        arguments: ["window;touch /tmp/tenx-command-runner-injection", "$(whoami)"],
        timeout: .seconds(1))

    #expect(output.json == .array([
        .string("window;touch /tmp/tenx-command-runner-injection"),
        .string("$(whoami)"),
    ]))
    #expect(!FileManager.default.fileExists(atPath: "/tmp/tenx-command-runner-injection"))
}

@Test func commandRunnerTerminatesTimedOutHelpers() async {
    let clock = ContinuousClock()
    let started = clock.now
    await #expect(throws: AgentDesktopCommandError.timedOut(executable: "sleep")) {
        try await AgentDesktopCommandRunner().run(
            executable: URL(filePath: "/bin/sleep"),
            arguments: ["2"],
            timeout: .milliseconds(20))
    }
    #expect(started.duration(to: clock.now) < .seconds(1))
}

private func makeArgumentPrinterFixture() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "tenx-command-runner-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appending(path: "argv-printer.c")
    let executable = directory.appending(path: "argv-printer")
    try """
    #include <stdio.h>
    int main(int argc, char *argv[]) {
        putchar('[');
        for (int i = 1; i < argc; i++) printf("%s\\\"%s\\\"", i == 1 ? "" : ",", argv[i]);
        puts("]");
        return 0;
    }
    """.write(to: source, atomically: true, encoding: .utf8)

    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
    compiler.arguments = ["clang", source.path, "-o", executable.path]
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else { throw FixtureError.compilationFailed }
    return executable
}

private enum FixtureError: Error { case compilationFailed }
