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

@Test func hammerspoonExecutableLocatorUsesSupportedHomebrewCandidatesInOrder() {
    let candidates = HammerspoonExecutableLocator.supportedCandidates

    #expect(candidates.map(\.path) == ["/opt/homebrew/bin/hs", "/usr/local/bin/hs"])
    #expect(HammerspoonExecutableLocator.locate(
        in: candidates,
        isExecutable: { _ in true }) == candidates[0])
    #expect(HammerspoonExecutableLocator.locate(
        in: candidates,
        isExecutable: { $0 == candidates[1] }) == candidates[1])
}

@MainActor @Test func hammerspoonModuleContractMatchesSetupInstructions() async throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let template = try String(
        contentsOf: repositoryRoot.appending(path: "App/Resources/Hammerspoon/tenx.lua"),
        encoding: .utf8)
    let model = ComputerUseSetupModel(automaticallyChecksReadiness: false)

    await model.perform(.showHammerspoonInstructions)

    #expect(template.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("return tenx"))
    #expect(model.instructions?.contains("tenx = require(\"tenx\")") == true)
}

@Test func hammerspoonProbeRequiresConfiguredSpaceToBeAUserSpace() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let template = try String(
        contentsOf: repositoryRoot.appending(path: "App/Resources/Hammerspoon/tenx.lua"),
        encoding: .utf8)

    #expect(template.contains("hs.spaces.spaceType"))
    #expect(template.contains("~= \"user\""))
}

@Test func hammerspoonSpaceOperationsVerifyTheirPostconditions() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let template = try String(
        contentsOf: repositoryRoot.appending(path: "App/Resources/Hammerspoon/tenx.lua"),
        encoding: .utf8)

    #expect(template.contains("hs.spaces.windowSpaces"))
    #expect(template.contains("hs.spaces.focusedSpace"))
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

@Test func aeroSpaceRequestsAndParsesTheRequiredWindowFields() async throws {
    let runner = FakeDesktopRunner(outputs: [
        .init(json: .array([
            .object([
                "window-id": .int(17),
                "app-name": .string("Notes"),
                "app-pid": .int(404),
                "workspace": .string("10x-abc123abc123"),
            ]),
        ]), exitStatus: 0),
    ])
    let provider = AeroSpaceProvider(executable: URL(filePath: "/bin/true"), runner: runner)

    let windows = try await provider.listWindows()

    #expect(windows == [AgentWindow(
        id: "17",
        processID: 404,
        app: "Notes",
        workspaceID: "10x-abc123abc123")])
    #expect(await runner.recordedArguments() == [[
        "list-windows",
        "--all",
        "--format",
        "%{window-id} %{app-name} %{app-pid} %{workspace}",
        "--json",
    ]])
}

@Test func aeroSpaceWatcherStartFailureIsTyped() async {
    let provider = AeroSpaceProvider(
        executable: URL(filePath: "/bin/true"),
        runner: FakeDesktopRunner(outputs: []),
        watcherPollInterval: .milliseconds(1))

    do {
        _ = try await provider.watchWindows()
        Issue.record("Expected watcher startup to fail")
    } catch let error as AgentDesktopProviderError {
        #expect(error == .operationFailed(.aeroSpace))
    } catch {
        Issue.record("Expected typed provider error")
    }
}

@Test func aeroSpaceWatcherSurfacesPostStartListFailure() async throws {
    let runner = FailingWatcherDesktopRunner(kind: .aeroSpace)
    let provider = AeroSpaceProvider(
        executable: URL(filePath: "/bin/true"),
        runner: runner,
        watcherPollInterval: .milliseconds(1))

    let stream = try await provider.watchWindows()
    var iterator = stream.makeAsyncIterator()

    #expect(await iterator.next() == .failed(.operationFailed(.aeroSpace)))
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

@Test func hammerspoonWatcherRejectsFailedHelperStartup() async {
    let runner = FakeDesktopRunner(outputs: [
        .init(json: .object(["ok": .bool(false)]), exitStatus: 0),
    ])
    let provider = HammerspoonProvider(
        executable: URL(filePath: "/bin/true"),
        runner: runner,
        watcherPollInterval: .milliseconds(1))

    do {
        _ = try await provider.watchWindows()
        Issue.record("Expected watcher startup to fail")
    } catch let error as AgentDesktopProviderError {
        #expect(error == .operationFailed(.hammerspoon))
    } catch {
        Issue.record("Expected typed provider error")
    }
}

@Test func hammerspoonWatcherSurfacesPostStartListFailureAndStopsHelper() async throws {
    let runner = FailingWatcherDesktopRunner(kind: .hammerspoon)
    let provider = HammerspoonProvider(
        executable: URL(filePath: "/bin/true"),
        runner: runner,
        watcherPollInterval: .milliseconds(1))

    let stream = try await provider.watchWindows()
    var iterator = stream.makeAsyncIterator()

    #expect(await iterator.next() == .failed(.operationFailed(.hammerspoon)))
    await runner.waitForStop()
}

private actor FakeDesktopRunner: AgentDesktopCommandRunning {
    private var outputs: [AgentDesktopCommandOutput]
    private var arguments: [[String]] = []

    init(outputs: [AgentDesktopCommandOutput]) {
        self.outputs = outputs
    }

    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> AgentDesktopCommandOutput {
        self.arguments.append(arguments)
        guard !outputs.isEmpty else { throw FakeDesktopRunnerError.noOutput }
        return outputs.removeFirst()
    }

    func recordedArguments() -> [[String]] { arguments }
}

private enum FakeDesktopRunnerError: Error { case noOutput }

private actor FailingWatcherDesktopRunner: AgentDesktopCommandRunning {
    private let kind: AgentDesktopProviderKind
    private var listCount = 0
    private var didStop = false
    private var stopContinuation: CheckedContinuation<Void, Never>?

    init(kind: AgentDesktopProviderKind) {
        self.kind = kind
    }

    func run(executable: URL, arguments: [String], timeout: Duration) async throws -> AgentDesktopCommandOutput {
        let command = arguments.last ?? ""
        if command.contains("stopWatcher") {
            didStop = true
            stopContinuation?.resume()
            stopContinuation = nil
            return .init(json: .object(["ok": .bool(true)]), exitStatus: 0)
        }
        if kind == .hammerspoon, command.contains("startWatcher") {
            return .init(json: .object(["ok": .bool(true)]), exitStatus: 0)
        }
        let isList = kind == .aeroSpace || command.contains("listWindows")
        if isList {
            listCount += 1
            if listCount == 1 { return .init(json: .array([]), exitStatus: 0) }
            throw FakeDesktopRunnerError.noOutput
        }
        return .init(json: .object(["ok": .bool(true)]), exitStatus: 0)
    }

    func waitForStop() async {
        guard !didStop else { return }
        await withCheckedContinuation { stopContinuation = $0 }
    }
}

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
