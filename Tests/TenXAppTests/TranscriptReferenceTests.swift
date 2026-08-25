import Testing
@testable import TenXApp

@Test func codeAndMarkdownAcceptRelativeFilesButPlainTextDoesNot() {
    #expect(TranscriptReference.extract(from: "`App/Foo.swift:8`") == [
        .file(path: "App/Foo.swift", line: 8),
    ])
    #expect(TranscriptReference.extract(from: "[Foo](App/Foo.swift)") == [
        .file(path: "App/Foo.swift", line: nil),
    ])
    #expect(TranscriptReference.extract(from: "Ignore words/with/slashes and relative/file.swift:2") == [])
}

@Test func codeAndMarkdownRejectRelativePathsWithEmptyExtensions() {
    #expect(TranscriptReference.extract(from: "`App/.gitignore`") == [])
    #expect(TranscriptReference.extract(from: "`App/Foo.`") == [])
    #expect(TranscriptReference.extract(from: "[Foo](App/.gitignore)") == [])
    #expect(TranscriptReference.extract(from: "[Foo](App/Foo.)") == [])
}

@Test func extractsCodeMarkdownAndPlainReferencesWithoutDuplicates() {
    let references = TranscriptReference.extract(from: """
    See `/Users/tannerpham/CS Projects/10x/App/Foo.swift:42`, then [the docs](https://example.com/guide?q=swift).
    The log is /tmp/tenx.log:7. The same file is `/Users/tannerpham/CS Projects/10x/App/Foo.swift:42`.
    """)

    #expect(references.count == 3)
    #expect(references[0] == .file(
        path: "/Users/tannerpham/CS Projects/10x/App/Foo.swift",
        line: 42))
    #expect(references[1] == .web(
        url: "https://example.com/guide?q=swift",
        label: "the docs"))
    #expect(references[2] == .file(path: "/tmp/tenx.log", line: 7))
}

@Test func referenceParserTrimsPunctuationAndRejectsLookalikes() {
    let references = TranscriptReference.extract(from: """
    Open https://example.com/one, or /tmp/file.swift:9.
    Ignore relative/file.swift:2 and words/with/slashes.
    """)

    #expect(references == [
        .web(url: "https://example.com/one", label: nil),
        .file(path: "/tmp/file.swift", line: 9),
    ])
}

@Test func plainAbsolutePathWithWhitespaceContinuationNeverUsesItsPrefix() {
    let references = TranscriptReference.extract(from: """
    Open /Users/tannerpham/CS Projects/.worktrees/10x/App/Sessions/MessageBubbleView.swift:1 next.
    """)

    #expect(references.isEmpty)
}
