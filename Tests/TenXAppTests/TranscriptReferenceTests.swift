import Testing
@testable import TenXApp

@Test func inlineFileReferencesRoundTripThroughAttributedLinks() throws {
    let reference = TranscriptReference.file(path: "App/Foo.swift", line: 8)
    let url = try #require(reference.inlineURL)

    #expect(TranscriptReference(inlineURL: url) == reference)
}

@Test func inlineMarkdownKeepsReferencesInTheirWrittenPosition() {
    let content = MessageContentParser.inline(
        "Open `App/Foo.swift:8` and [the docs](https://example.com/docs).")
    let references = content.attributed.runs
        .compactMap(\.link)
        .compactMap(TranscriptReference.init(inlineURL:))

    #expect(references == [
        .file(path: "App/Foo.swift", line: 8),
        .web(url: "https://example.com/docs", label: nil),
    ])
}

@Test func codeAndMarkdownAcceptRelativeFilesButPlainTextDoesNot() {
    #expect(TranscriptReference.extract(from: "`App/Foo.swift:8`") == [
        .file(path: "App/Foo.swift", line: 8),
    ])
    #expect(TranscriptReference.extract(from: "[Foo](App/Foo.swift)") == [
        .file(path: "App/Foo.swift", line: nil),
    ])
    #expect(TranscriptReference.extract(from: "Ignore words/with/slashes and relative/file.swift:2") == [])
}

@Test func codeAndMarkdownAcceptRootFilesButRejectVersionNumbers() {
    #expect(TranscriptReference.extract(from: "Open `Package.swift` and [README](README.md).") == [
        .file(path: "Package.swift", line: nil),
        .file(path: "README.md", line: nil),
    ])
    #expect(TranscriptReference.extract(from: "Version `1.2` is current.").isEmpty)
    #expect(TranscriptReference.extract(from: "[Email](mailto:dev@example.com)").isEmpty)
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

@Test func virtualResourceSchemesAreNotPresentedAsLocalFiles() {
    #expect(TranscriptReference.parseInline("omp://models.md") == nil)
    #expect(TranscriptReference.parseInline("local://implementation-plan.md") == nil)
}

@Test func plainAbsolutePathWithWhitespaceContinuationNeverUsesItsPrefix() {
    let references = TranscriptReference.extract(from: """
    Open /Users/tannerpham/CS Projects/.worktrees/10x/App/Sessions/MessageBubbleView.swift:1 next.
    """)

    #expect(references.isEmpty)
}

@Test func adjacentPlainAbsolutePathsRemainSeparateReferences() {
    let references = TranscriptReference.extract(from: "Compare /tmp/one.swift /tmp/two.swift")

    #expect(references == [
        .file(path: "/tmp/one.swift", line: nil),
        .file(path: "/tmp/two.swift", line: nil),
    ])
}

@Test func extensionBearingAbsolutePrefixWithWhitespaceContinuationIsRejected() {
    let references = TranscriptReference.extract(from: "Open /tmp/one.swift child/file.swift")

    #expect(references.isEmpty)
}

@Test func plainWebReferenceIgnoresFileWhitespaceContinuation() {
    let references = TranscriptReference.extract(from: "See https://example.com child/file.swift")

    #expect(references == [
        .web(url: "https://example.com", label: nil),
    ])
}
