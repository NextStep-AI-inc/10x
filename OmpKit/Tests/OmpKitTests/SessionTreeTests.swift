import Testing
import Foundation
@testable import OmpKit

func testHeader() -> SessionHeader {
    SessionHeader(id: "test", cwd: "/tmp", timestamp: "2026-01-01T00:00:00Z",
                  version: 3, title: nil, titleSource: nil, parentSession: nil)
}

private func node(_ id: String, _ parent: String?) -> SessionEntry {
    .resetBoundary(base: SessionEntryBase(id: id, parentId: parent, timestamp: "t"))
}

private func file(_ entries: [SessionEntry]) -> ParsedSessionFile {
    ParsedSessionFile(header: testHeader(), entries: entries, malformedLineCount: 0)
}

@Test func linearChainReturnsEveryEntryInOrder() {
    let entries = [node("a", nil), node("b", "a"), node("c", "b")]
    #expect(SessionTree.activePath(of: file(entries)).map(\.base.id) == ["a", "b", "c"])
}

@Test func branchResolvesToFileOrderLeaf() throws {
    // a ← b (first branch tip), a ← c (second tip, later in file) ⇒ path is [a, c]
    let a = node("a", nil), b = node("b", "a"), c = node("c", "a")
    #expect(SessionTree.activePath(of: file([a, b, c])).map(\.base.id) == ["a", "c"])
}

@Test func explicitLeafSelectsItsOwnBranch() {
    let entries = [node("a", nil), node("b", "a"), node("c", "a")]
    let path = SessionTree.activePath(entries: entries, leafId: "b")
    #expect(path.map(\.base.id) == ["a", "b"])
}

@Test func parentCycleTerminates() {
    // Corrupt: a ↔ b point at each other.
    let entries = [node("a", "b"), node("b", "a")]
    let path = SessionTree.activePath(of: file(entries))
    #expect(path.count <= 2)   // terminates rather than looping forever
}

@Test func emptyEntriesGiveEmptyPath() {
    #expect(SessionTree.activePath(of: file([])).isEmpty)
}

@Test func missingParentStopsTheWalk() {
    // "b" references a parent that is not in the file (e.g. pre-compaction).
    let entries = [node("b", "gone")]
    #expect(SessionTree.activePath(of: file(entries)).map(\.base.id) == ["b"])
}

@Test func compactedPrefixHidesEntriesBeforeFirstKept() {
    let a = node("a", nil)
    let b = node("b", "a")
    let compaction = SessionEntry.compaction(
        base: SessionEntryBase(id: "cmp", parentId: "b", timestamp: "t"),
        value: SessionCompaction(
            summary: "earlier work",
            shortSummary: nil,
            firstKeptEntryId: "c",
            tokensBefore: nil,
            tokensAfter: nil,
            method: nil,
            warning: nil))
    let c = node("c", "cmp")
    let path = SessionTree.activePath(of: file([a, b, compaction, c]))
    guard let result = SessionTree.compactedPrefix(of: path) else {
        Issue.record("expected a compaction"); return
    }
    #expect(result.summary == "earlier work")
    #expect(result.hidden.map(\.base.id) == ["a", "b", "cmp"])
}

@Test func compactedPrefixIsNilWithoutCompaction() {
    let path = SessionTree.activePath(of: file([node("a", nil), node("b", "a")]))
    #expect(SessionTree.compactedPrefix(of: path) == nil)
}
