import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func railPresentationKeepsEverySessionVisibleWhenCollapsed() {
    let first = metadata(path: "/sessions/first.jsonl", title: "First")
    let second = metadata(path: "/sessions/second.jsonl", title: "Second")
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: [first, second])

    let items = RailPresentation.items(groups: [group], selectedSessionPath: second.path)

    #expect(items.map(\.id) == [
        "project:/tmp/project",
        "session:/sessions/first.jsonl",
        "session:/sessions/second.jsonl",
    ])
    #expect(items.map(\.markerLabel) == ["PR", "01", "02"])
    #expect(items.map(\.treePosition) == [.root, .child, .terminalChild])
    #expect(items.filter { $0.kind == .session }.count == 2)
    #expect(items.first { $0.id == "session:/sessions/second.jsonl" }?.isSelected == true)
}

@Test func sessionItemShowsComputerBadgeWhenActive() {
    let session = metadata(path: "/sessions/active.jsonl", title: "Active")
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: [session])

    let items = RailPresentation.items(
        groups: [group],
        selectedSessionPath: session.path,
        computerUseActivePaths: [session.path])

    let sessionItem = items.first { $0.kind == .session }
    #expect(sessionItem?.hasComputerUse == true)
}

@Test func sessionItemHidesComputerBadgeWhenInactive() {
    let session = metadata(path: "/sessions/idle.jsonl", title: "Idle")
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/project", directoryHint: .isDirectory),
        sessions: [session])

    let items = RailPresentation.items(
        groups: [group],
        selectedSessionPath: session.path,
        computerUseActivePaths: [])

    let sessionItem = items.first { $0.kind == .session }
    #expect(sessionItem?.hasComputerUse == false)
}

@Test func projectMarkerUsesInitialsForMultiwordNames() {
    let group = ProjectSessionGroup(
        projectURL: URL(filePath: "/tmp/NextStep-Workspace", directoryHint: .isDirectory),
        sessions: [])

    let items = RailPresentation.items(groups: [group], selectedSessionPath: nil)

    #expect(items.map(\.markerLabel) == ["NW"])
}

private func metadata(path: String, title: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/project",
        title: title,
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 10,
        status: .complete)
}
