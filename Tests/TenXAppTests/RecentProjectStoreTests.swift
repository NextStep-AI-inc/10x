import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func explicitProjectsRankBeforeSessionHistoryAndDeduplicate() throws {
    let fixture = try RecentProjectFixture()
    defer { fixture.cleanup() }
    let first = try fixture.directory("Explicit")
    let second = try fixture.directory("Session")
    let store = fixture.store()
    store.recordSelection(first)

    let projects = store.rankedProjects(sessions: [
        fixture.session(cwd: second.path, modified: Date(timeIntervalSince1970: 20)),
        fixture.session(cwd: first.path, modified: Date(timeIntervalSince1970: 30)),
    ])

    #expect(projects == [first.resolvingSymlinksInPath(), second.resolvingSymlinksInPath()])
}

@MainActor
@Test func recordSelectionMovesAProjectToTheFrontAcrossStoreInstances() throws {
    let fixture = try RecentProjectFixture()
    defer { fixture.cleanup() }
    let first = try fixture.directory("First")
    let second = try fixture.directory("Second")
    fixture.store().recordSelection(first)
    fixture.store().recordSelection(second)
    fixture.store().recordSelection(first)

    #expect(fixture.store().rankedProjects(sessions: []) == [
        first.resolvingSymlinksInPath(),
        second.resolvingSymlinksInPath(),
    ])
}

@MainActor
@Test func rankingFiltersMissingFilesAndStopsAtTwoProjects() throws {
    let fixture = try RecentProjectFixture()
    defer { fixture.cleanup() }
    let first = try fixture.directory("One")
    let second = try fixture.directory("Two")
    let third = try fixture.directory("Three")
    let missing = fixture.root.appending(path: "Deleted", directoryHint: .isDirectory)

    let projects = fixture.store().rankedProjects(sessions: [
        fixture.session(cwd: missing.path, modified: Date(timeIntervalSince1970: 40)),
        fixture.session(cwd: first.path, modified: Date(timeIntervalSince1970: 30)),
        fixture.session(cwd: second.path, modified: Date(timeIntervalSince1970: 20)),
        fixture.session(cwd: third.path, modified: Date(timeIntervalSince1970: 10)),
    ])

    #expect(projects == [first.resolvingSymlinksInPath(), second.resolvingSymlinksInPath()])
}

private final class RecentProjectFixture {
    let root: URL
    private let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "RecentProjectStoreTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func directory(_ name: String) throws -> URL {
        let directory = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    func store() -> RecentProjectStore {
        RecentProjectStore(defaults: defaults)
    }

    func session(cwd: String, modified: Date) -> SessionMetadata {
        SessionMetadata(
            path: root.appending(path: "\(UUID().uuidString).jsonl").path,
            sessionId: UUID().uuidString,
            cwd: cwd,
            title: nil,
            created: modified,
            modified: modified,
            sizeBytes: 10,
            status: .complete)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
