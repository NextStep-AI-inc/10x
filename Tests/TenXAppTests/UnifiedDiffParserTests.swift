import Testing
@testable import TenXApp

@Test func parsesMultiFileDiffsAndLineNumberProgression() throws {
    let diff = try #require(UnifiedDiffParser.parse("""
    diff --git a/App/A.swift b/App/A.swift
    --- a/App/A.swift
    +++ b/App/A.swift
    @@ -10,3 +10,4 @@ func value() {
     context
    -old
    +new
    +added
     tail
    diff --git a/App/B.swift b/App/B.swift
    --- a/App/B.swift
    +++ b/App/B.swift
    @@ -1 +1 @@
    -before
    +after
    """))

    #expect(diff.files.count == 2)
    #expect(diff.files.map(\.path) == ["App/A.swift", "App/B.swift"])
    let lines = try #require(diff.files.first?.hunks.first?.lines)
    #expect(lines.map(\.oldLine) == [10, 11, nil, nil, 12])
    #expect(lines.map(\.newLine) == [10, nil, 11, 12, 13])
    #expect(diff.files[0].additions == 2)
    #expect(diff.files[0].removals == 1)
}

@Test func parserPreservesNoNewlineMarkersAndRawPatch() throws {
    let raw = #"""
    --- a/value.txt
    +++ b/value.txt
    @@ -1 +1 @@
    -old
    \ No newline at end of file
    +new
    \ No newline at end of file
    """#
    let diff = try #require(UnifiedDiffParser.parse(raw))
    #expect(diff.raw == raw)
    #expect(diff.files[0].hunks[0].lines.filter { $0.kind == .noNewline }.count == 2)
}

@Test func malformedInputFailsClosedAndHeaderlessPatchUsesFallbackPath() throws {
    #expect(UnifiedDiffParser.parse("ordinary output") == nil)

    let diff = try #require(UnifiedDiffParser.parse("""
    @@ -1 +1 @@
    -old
    +new
    """, fallbackPath: "/tmp/App.swift"))
    #expect(diff.files.map(\.path) == ["/tmp/App.swift"])
}

@Test func longContextRunsCollapseWithoutLosingLineIndexes() throws {
    let diff = try #require(UnifiedDiffParser.parse("""
    --- a/App.swift
    +++ b/App.swift
    @@ -1,10 +1,10 @@
     one
     two
     three
     four
     five
     six
     seven
     eight
    -old
    +new
    """))
    let hunk = try #require(diff.files.first?.hunks.first)
    let rows = hunk.displayRows(context: 2)
    let collapsed = rows.compactMap { row -> Int? in
        guard case .collapsed(_, let count, _) = row else { return nil }
        return count
    }
    #expect(collapsed == [4])
    #expect(rows.compactMap(\.lineIndex) == [0, 1, 6, 7, 8, 9])
}

@Test func collapsedContextHasTheExactHiddenLineCount() throws {
    let diff = try #require(UnifiedDiffParser.parse("""
    --- a/App.swift
    +++ b/App.swift
    @@ -1,8 +1,8 @@
     one
     two
     three
     four
     five
     six
     seven
     eight
    """))
    let rows = try #require(diff.files.first?.hunks.first?.displayRows(context: 2))
    let collapsed = try #require(rows.first { row in
        if case .collapsed = row { return true }
        return false
    })

    guard case .collapsed(_, let count, let indices) = collapsed else {
        Issue.record("Expected collapsed context")
        return
    }
    #expect(count == 4)
    #expect(indices == [2, 3, 4, 5])
}
