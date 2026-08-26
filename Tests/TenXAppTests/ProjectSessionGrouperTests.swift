import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func groupsSessionsByProjectWithNewestFirst() {
    let oldest = session(path: "/sessions/old.jsonl", cwd: "/tmp/alpha", modified: 10)
    let newest = session(path: "/sessions/new.jsonl", cwd: "/tmp/alpha", modified: 30)
    let middle = session(path: "/sessions/middle.jsonl", cwd: "/tmp/beta", modified: 20)

    let groups = ProjectSessionGrouper.groups([oldest, newest, middle])

    #expect(groups.map(\.projectURL.path) == ["/tmp/alpha", "/tmp/beta"])
    #expect(groups[0].sessions.map(\.path) == [newest.path, oldest.path])
    #expect(groups[1].sessions.map(\.path) == [middle.path])
}

@Test func emptyWorkingDirectoryIsKeptAsUnknownProject() {
    let metadata = session(path: "/sessions/unknown.jsonl", cwd: "", modified: 10)

    let groups = ProjectSessionGrouper.groups([metadata])

    #expect(groups.count == 1)
    #expect(groups[0].displayName == "Unknown Project")
    #expect(groups[0].sessions == [metadata])
}

@Test func choosableProjectURLsSkipsUnknownAndIncludesSelected() {
    let known = session(path: "/sessions/a.jsonl", cwd: "/tmp/alpha", modified: 10)
    let unknown = session(path: "/sessions/u.jsonl", cwd: "", modified: 20)
    let selected = URL(filePath: "/tmp/new-folder", directoryHint: .isDirectory)

    let urls = ProjectSessionGrouper.choosableProjectURLs(
        from: [known, unknown],
        including: selected)

    #expect(urls.map(\.path) == ["/tmp/new-folder", "/tmp/alpha"])
}

@Test func choosableProjectURLsDoesNotDuplicateSelected() {
    let known = session(path: "/sessions/a.jsonl", cwd: "/tmp/alpha", modified: 10)
    let selected = URL(filePath: "/tmp/alpha", directoryHint: .isDirectory)

    let urls = ProjectSessionGrouper.choosableProjectURLs(
        from: [known],
        including: selected)

    #expect(urls.map(\.path) == ["/tmp/alpha"])
}

private func session(path: String, cwd: String, modified: TimeInterval) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: cwd,
        title: nil,
        created: Date(timeIntervalSince1970: modified),
        modified: Date(timeIntervalSince1970: modified),
        sizeBytes: 10,
        status: .complete)
}
