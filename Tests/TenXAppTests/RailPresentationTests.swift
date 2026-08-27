import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func railPresentationLimitsCollapsedProjectsToFiveSessions() {
    let sessions = sessionMetadata(count: 7)
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: sessions)

    let items = RailPresentation.items(groups: [group], selectedSessionPath: sessions[6].path)

    #expect(items.map(\.id) == [
        "project:/tmp/project",
        "session:/sessions/1.jsonl",
        "session:/sessions/2.jsonl",
        "session:/sessions/3.jsonl",
        "session:/sessions/4.jsonl",
        "session:/sessions/5.jsonl",
        "disclosure:/tmp/project",
    ])
    #expect(items.map(\.markerLabel) == ["PR", "01", "02", "03", "04", "05", "..."])
    #expect(items.map(\.treePosition) == [
        .root, .child, .child, .child, .child, .child, .terminalChild,
    ])
    #expect(items.filter { $0.kind == .session }.count == RailPresentation.recentSessionLimit)
    #expect(items.last?.kind == .disclosure)
    #expect(items.last?.disclosure == RailProjectDisclosure(
        projectID: group.id,
        hiddenCount: 2,
        isExpanded: false))
    #expect(items.filter(\.isSelected).isEmpty)
}

@Test func railPresentationShowsEverySessionForExpandedProjects() {
    let sessions = sessionMetadata(count: 7)
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: sessions)

    let items = RailPresentation.items(
        groups: [group],
        selectedSessionPath: sessions[6].path,
        expandedProjectIDs: [group.id])

    #expect(items.map(\.id) == [
        "project:/tmp/project",
        "session:/sessions/1.jsonl",
        "session:/sessions/2.jsonl",
        "session:/sessions/3.jsonl",
        "session:/sessions/4.jsonl",
        "session:/sessions/5.jsonl",
        "session:/sessions/6.jsonl",
        "session:/sessions/7.jsonl",
        "disclosure:/tmp/project",
    ])
    #expect(items.last?.disclosure == RailProjectDisclosure(
        projectID: group.id,
        hiddenCount: 2,
        isExpanded: true))
    #expect(items.filter(\.isSelected).map(\.id) == ["session:/sessions/7.jsonl"])
}

@Test func railPresentationOmitsDisclosureForFiveSessions() {
    let sessions = sessionMetadata(count: 5)
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: sessions)

    let items = RailPresentation.items(groups: [group], selectedSessionPath: nil)

    #expect(items.count == 6)
    #expect(items.contains { $0.kind == .disclosure } == false)
    #expect(items.last?.treePosition == .terminalChild)
}

@Test func railPresentationEmitsOnlyTheProjectItemForAGroupWithNoSessions() {
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/empty-project", directoryHint: .isDirectory),
        sessions: [])

    let items = RailPresentation.items(groups: [group], selectedSessionPath: nil)

    #expect(items.count == 1)
    #expect(items.map(\.id) == ["project:/tmp/empty-project"])
    #expect(items[0].kind == .project)
    #expect(items[0].treePosition == .root)
    #expect(items.contains { $0.kind == .disclosure } == false)
}

@Test func projectMarkerUsesInitialsForMultiwordNames() {
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/NextStep-Workspace", directoryHint: .isDirectory),
        sessions: [])

    let items = RailPresentation.items(groups: [group], selectedSessionPath: nil)

    #expect(items.map(\.markerLabel) == ["NW"])
}

private func sessionMetadata(count: Int) -> [SessionMetadata] {
    (1...count).map { index in
        metadata(
            path: "/sessions/\(index).jsonl",
            title: "Session \(index)",
            modified: Date(timeIntervalSince1970: TimeInterval(count - index)))
    }
}

private func metadata(
    path: String,
    title: String,
    modified: Date = .distantPast
) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/project",
        title: title,
        created: .distantPast,
        modified: modified,
        sizeBytes: 10,
        status: .complete)
}
