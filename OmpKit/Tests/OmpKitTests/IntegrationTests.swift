import Testing
import Foundation
@testable import OmpKit

/// Runs only when OMPKIT_INTEGRATION=1 — needs `omp` on PATH. No model calls are made.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OMPKIT_INTEGRATION"] == "1"))
func realOmpReadyStateRoundTrip() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ompkit-int-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    var cfg = RpcClientConfiguration()
    cfg.cwd = tmp
    cfg.noSession = true
    let c = RpcClient(configuration: cfg)
    let ready = try await c.start()
    #expect(ready.supportedProtocolVersions?.contains(2) == true)
    #expect(ready.maxFrameBytes == 1_048_576)
    #expect(await c.negotiatedProtocolVersion == 2)

    let state = try await c.send(.getState(), timeout: .seconds(20))
    #expect(state.success)
    #expect(state.data?["sessionId"]?.stringValue?.isEmpty == false)
    #expect(state.data?["isStreaming"]?.boolValue == false)
    await c.shutdown()
}

/// Proves the real OMP launch contract used by 10x creates two independently
/// persisted session identities in one project even when autoResume is enabled.
/// No model calls are made.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OMPKIT_INTEGRATION"] == "1"))
func realManagerCreatesDistinctPersistentSessionsInOneProject() async throws {
    let project = FileManager.default.temporaryDirectory
        .appendingPathComponent("ompkit-fresh-\(UUID().uuidString)", isDirectory: true)
    let sessionDirectory = URL(
        filePath: expectedFreshSessionDirectory(for: project.path),
        directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: project) }
    defer { try? FileManager.default.removeItem(at: sessionDirectory) }

    let executable = ProcessInfo.processInfo.environment["OMPKIT_EXECUTABLE"] ?? "omp"
    let manager = SessionProcessManager(executable: executable)
    let first = try await manager.openNew(projectDirectory: project.path)
    let second = try await manager.openNew(projectDirectory: project.path)

    let expectedDirectory = sessionDirectory.path
    #expect(first.sessionPath != second.sessionPath)
    #expect(first.sessionPath.hasPrefix(expectedDirectory + "/"))
    #expect(second.sessionPath.hasPrefix(expectedDirectory + "/"))
    #expect(first.sessionPath.hasSuffix(".jsonl"))
    #expect(second.sessionPath.hasSuffix(".jsonl"))
    await manager.closeAll()
}

/// Reads the real session library on this machine: proves the on-disk contract
/// against files omp actually wrote, not just fixtures.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OMPKIT_INTEGRATION"] == "1"))
func realSessionLibraryParses() async throws {
    let library = SessionLibrary()
    let sessions = await library.listAll()
    guard !sessions.isEmpty else {
        Issue.record("no omp sessions found on this machine — cannot verify the contract")
        return
    }
    // Every listed session must carry the header fields the UI depends on.
    for session in sessions.prefix(50) {
        #expect(!session.sessionId.isEmpty)
        #expect(!session.cwd.isEmpty)
        #expect(session.sizeBytes > 0)
    }
    // The newest session must parse end to end and produce a walkable path.
    let newest = sessions[0]
    let data = try Data(contentsOf: URL(fileURLWithPath: newest.path))
    let parsed = try SessionFileParser.parse(data: data)
    #expect(parsed.header.id == newest.sessionId)
    let path = SessionTree.activePath(of: parsed)
    #expect(path.count <= parsed.entries.count)
    if !parsed.entries.isEmpty { #expect(!path.isEmpty) }
}
