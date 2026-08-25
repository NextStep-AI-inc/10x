import Foundation
import Testing
@testable import TenXApp

@Test func backgroundProviderReportsExplicitlyDegradedCapabilities() async {
    let provider = BackgroundProvider()
    let probe = await provider.probe()

    #expect(probe.availability == .healthy)
    #expect(!probe.capabilities.canIsolate)
    #expect(!probe.capabilities.canMoveWithoutFocus)
    #expect(!probe.capabilities.canCaptureOffscreen)
    #expect(!probe.capabilities.canInputInBackground)
}

@Test func aeroSpaceWorkspaceIDsRejectUnsafeSessionTokens() async {
    let provider = AeroSpaceProvider()

    await #expect(throws: AgentDesktopProviderError.self) {
        try await provider.prepare(sessionToken: "unsafe token;workspace")
    }
}

@Test func aeroSpaceRejectsAnyMalformedWindowInASnapshot() async {
    let runner = FakeDesktopRunner(outputs: [
        .init(json: .array([
            .object([
                "window-id": .int(7),
                "app-name": .string("Notes"),
                "app-pid": .string("not-a-pid"),
                "workspace": .string("1"),
            ]),
        ]), exitStatus: 0),
    ])
    let provider = AeroSpaceProvider(executable: URL(filePath: "/bin/true"), runner: runner)

    await #expect(throws: AgentDesktopProviderError.self) {
        try await provider.listWindows()
    }
}

@Test func hammerspoonRejectsAnyMalformedWindowInASnapshot() async {
    let runner = FakeDesktopRunner(outputs: [
        .init(json: .array([
            .object([
                "id": .string("7"),
                "app": .string("Notes"),
            ]),
        ]), exitStatus: 0),
    ])
    let provider = HammerspoonProvider(executable: URL(filePath: "/bin/true"), runner: runner)

    await #expect(throws: AgentDesktopProviderError.self) {
        try await provider.listWindows()
    }
}

@Test func hammerspoonRejectsFalseHelperResults() async {
    let runner = FakeDesktopRunner(outputs: [
        .init(json: .object(["ok": .bool(false)]), exitStatus: 0),
    ])
    let provider = HammerspoonProvider(executable: URL(filePath: "/bin/true"), runner: runner)

    await #expect(throws: AgentDesktopProviderError.self) {
        try await provider.move(windowID: "12", to: "34")
    }
}

@Test func hammerspoonRejectsNonDecimalWindowAndSpaceIDs() async {
    let runner = FakeDesktopRunner(outputs: [
        .init(json: .object(["ok": .bool(true)]), exitStatus: 0),
    ])
    let provider = HammerspoonProvider(executable: URL(filePath: "/bin/true"), runner: runner)

    await #expect(throws: AgentDesktopProviderError.self) {
        try await provider.move(windowID: "12", to: "space-2")
    }
}

@Test func hammerspoonWatcherStopsWhenItsStreamIsCancelled() async throws {
    let runner = WatchingDesktopRunner()
    let provider = HammerspoonProvider(executable: URL(filePath: "/bin/true"), runner: runner)
    let stream = try await provider.watchWindows()
    let consumer = Task {
        for await _ in stream {}
    }

    await Task.yield()
    consumer.cancel()
    await runner.waitForStop()
}

private actor FakeDesktopRunner: AgentDesktopCommandRunning {
    private var outputs: [AgentDesktopCommandOutput]

    init(outputs: [AgentDesktopCommandOutput]) {
        self.outputs = outputs
    }

    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> AgentDesktopCommandOutput {
        guard !outputs.isEmpty else { throw FakeDesktopRunnerError.noOutput }
        return outputs.removeFirst()
    }
}

private enum FakeDesktopRunnerError: Error { case noOutput }

private actor WatchingDesktopRunner: AgentDesktopCommandRunning {
    private var didStop = false
    private var stopContinuation: CheckedContinuation<Void, Never>?

    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> AgentDesktopCommandOutput {
        let command = arguments.last ?? ""
        if command.contains("stopWatcher") {
            didStop = true
            stopContinuation?.resume()
            stopContinuation = nil
        }
        if command.contains("listWindows") {
            return .init(json: .array([]), exitStatus: 0)
        }
        return .init(json: .object(["ok": .bool(true)]), exitStatus: 0)
    }

    func waitForStop() async {
        guard !didStop else { return }
        await withCheckedContinuation { continuation in
            stopContinuation = continuation
        }
    }
}
