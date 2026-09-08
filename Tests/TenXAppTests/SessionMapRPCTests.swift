import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func sessionMapRPCWaitsForTerminalOutputAndReapsChild() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "session-map-rpc-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let pidFile = root.appending(path: "child.pid")
    let configurationFile = root.appending(path: "configuration.json")
    let executable = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/session_map_fake_server.py")
    var environment = OmpProcessEnvironment.resolved()
    environment["SESSION_MAP_FAKE_CASE"] = "partial-final"
    environment["SESSION_MAP_FAKE_PID_FILE"] = pidFile.path
    environment["SESSION_MAP_FAKE_CONFIGURATION_FILE"] = configurationFile.path
    let rpc = SessionMapRPC(
        executableURL: executable,
        projectURL: root,
        environment: environment,
        deadline: .seconds(3))

    let output = try await rpc.complete(
        prompt: "Build the map",
        images: [],
        model: SessionMapResolvedModel(
            provider: "fixture", modelID: "writer", effort: "low", acceptsImages: false))

    #expect(output.contains("Final map"))
    #expect(!output.contains("Partial map"))
    let configuration = try JSONDecoder().decode(
        RecordedMapRPCConfiguration.self,
        from: Data(contentsOf: configurationFile))
    #expect(URL(filePath: configuration.cwd).resolvingSymlinksInPath().path
        == root.resolvingSymlinksInPath().path)
    #expect(configuration.argv == [
        "--mode", "rpc", "--no-title",
        "--provider", "fixture", "--model", "writer", "--thinking", "low",
        "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-rules",
    ])
    let pid = try #require(Int32(
        String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
    #expect(kill(pid, 0) == -1)
}

@Test(arguments: ["timeout", "eof", "provider-error"])
func sessionMapRPCFailureReapsChild(caseName: String) async throws {
    let fixture = try makeRPCFixture(caseName: caseName)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    do {
        _ = try await fixture.rpc.complete(prompt: "Build", images: [], model: fixture.model)
        Issue.record("Expected \(caseName) to fail")
    } catch {
        switch caseName {
        case "timeout": #expect(error as? SessionMapRPCError == .deadlineExceeded)
        case "eof": #expect(error as? SessionMapRPCError == .streamEnded)
        case "provider-error":
            #expect(error as? SessionMapRPCError == .provider("fixture provider unavailable"))
        default: Issue.record("Unexpected fixture case \(caseName)")
        }
    }
    let pid = try await waitForPID(at: fixture.pidFile)
    #expect(kill(pid, 0) == -1)
}

@Test func sessionMapRPCCancelledStartupReapsChild() async throws {
    let fixture = try makeRPCFixture(caseName: "cancelled-startup")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let task = Task {
        try await fixture.rpc.complete(prompt: "Build", images: [], model: fixture.model)
    }
    let pid = try await waitForPID(at: fixture.pidFile)
    task.cancel()
    _ = try? await task.value
    for _ in 0..<100 where kill(pid, 0) == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(kill(pid, 0) == -1)
}

@Test func sessionMapRPCReturnsMalformedFinalForBoundedGeneratorRepair() async throws {
    let fixture = try makeRPCFixture(caseName: "malformed-final")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let output = try await fixture.rpc.complete(prompt: "Build", images: [], model: fixture.model)
    #expect(output == "not xml")
}

private struct RPCFixture {
    let root: URL
    let pidFile: URL
    let rpc: SessionMapRPC
    let model: SessionMapResolvedModel
}

private func makeRPCFixture(caseName: String) throws -> RPCFixture {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "session-map-rpc-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let pidFile = root.appending(path: "child.pid")
    let executable = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/session_map_fake_server.py")
    var environment = OmpProcessEnvironment.resolved()
    environment["SESSION_MAP_FAKE_CASE"] = caseName
    environment["SESSION_MAP_FAKE_PID_FILE"] = pidFile.path
    return RPCFixture(
        root: root,
        pidFile: pidFile,
        rpc: SessionMapRPC(
            executableURL: executable,
            projectURL: root,
            environment: environment,
            deadline: caseName == "timeout" ? .milliseconds(100) : .seconds(3)),
        model: SessionMapResolvedModel(
            provider: "fixture", modelID: "writer", effort: "low", acceptsImages: false))
}

private func waitForPID(at url: URL) async throws -> Int32 {
    for _ in 0..<100 {
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return pid
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw MapRPCTestError.missingPID
}

private enum MapRPCTestError: Error { case missingPID }

private struct RecordedMapRPCConfiguration: Decodable {
    let argv: [String]
    let cwd: String
}
