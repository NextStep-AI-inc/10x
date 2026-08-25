import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func openSettingsSelectsSettingsRoute() {
    let model = AppModel()

    model.openSettings()

    #expect(model.route == .settings)
}

@MainActor
@Test func openNewSessionSelectsNewSessionRoute() {
    let model = AppModel()
    model.route = .settings

    model.openNewSession()

    #expect(model.route == .newSession)
}

@MainActor
@Test func openSearchPresentsSearchWithoutChangingRoute() {
    let model = AppModel()
    model.route = .session("/tmp/session.jsonl")

    model.openSearch()

    #expect(model.isSearchPresented)
    #expect(model.route == .session("/tmp/session.jsonl"))
}

@MainActor
@Test func openArchivedSessionsSelectsArchivedRoute() {
    let model = AppModel()

    model.openArchivedSessions()

    #expect(model.route == .archivedSessions)
}

@MainActor
@Test func projectDeletionCopyNamesCountAndProtectsProjectFiles() {
    let model = AppModel()
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/Project", directoryHint: .isDirectory),
        sessions: [
            navigationMetadata("/sessions/one.jsonl"),
            navigationMetadata("/sessions/two.jsonl"),
        ])

    model.requestDeleteProject(group)

    #expect(model.pendingDeletion?.title == "Delete sessions for Project?")
    #expect(model.pendingDeletion?.message
        == "This permanently deletes 2 session transcripts. Project files are not changed.")
    #expect(model.pendingDeletion?.paths == group.sessions.map(\.path))
}

@MainActor
@Test func projectDeletionCopyUsesSingularTranscript() {
    let model = AppModel()
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/Project", directoryHint: .isDirectory),
        sessions: [navigationMetadata("/sessions/one.jsonl")])

    model.requestDeleteProject(group)

    #expect(model.pendingDeletion?.message
        == "This permanently deletes 1 session transcript. Project files are not changed.")
}

@MainActor
@Test func sessionDeletionRequestHasExactIdentityAndCopy() {
    let model = AppModel()
    let session = navigationMetadata("/sessions/one.jsonl")

    model.requestDeleteSession(session)

    #expect(model.pendingDeletion?.id == "session:/sessions/one.jsonl")
    #expect(model.pendingDeletion?.paths == [session.path])
    #expect(model.pendingDeletion?.title == "Delete Session?")
    #expect(model.pendingDeletion?.message
        == "This permanently deletes the session transcript. Project files are not changed.")
    #expect(model.pendingDeletion?.errorSubject == "Session")
}

@MainActor
@Test func archivingTheOpenRouteReturnsToNewSession() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-archive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    let activeRoot = container.appendingPathComponent("sessions")
    let archiveRoot = container.appendingPathComponent("archived-sessions")
    let file = activeRoot.appendingPathComponent("-tmp-project/open.jsonl")
    try writeNavigationSession(at: file, id: "open", cwd: "/tmp/project")
    let library = SessionLibrary(root: activeRoot, archiveRoot: archiveRoot)
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: library))
    await model.reloadSessions()
    let session = try #require(model.sessions.first)
    model.route = .session(session.path)

    await model.archiveSession(session)

    #expect(model.route == .newSession)
    #expect(model.activeSession == nil)
    #expect(model.sessions.isEmpty)
    #expect(model.archivedSessions.map(\.sessionId) == ["open"])
}

@MainActor
@Test func failedArchiveNamesUnchangedSessionFile() async {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-failed-archive-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    let library = SessionLibrary(root: container.appendingPathComponent("sessions"))
    let model = AppModel(dependencies: AppDependencies(
        ompLocator: MissingOmpLocator(),
        sessionLibrary: library))
    let missing = navigationMetadata(
        container.appendingPathComponent("sessions/bucket/missing.jsonl").path)

    await model.archiveSession(missing)

    #expect(model.sessionActionError
        == "Could not archive Session. 1 session file remains unchanged.")
}

private func navigationMetadata(_ path: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/Project",
        title: "Session",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 10,
        status: .complete)
}

private func writeNavigationSession(at url: URL, id: String, cwd: String) throws {
    let content = """
    {"type":"session","version":3,"id":"\(id)","timestamp":"2026-01-01T00:00:00.000Z","cwd":"\(cwd)"}
    {"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","content":"done"}}
    """
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try Data(content.utf8).write(to: url)
}

private struct MissingOmpLocator: OmpLocating {
    func locate(preferredURL: URL?) async -> OmpInstallation? { nil }
}
