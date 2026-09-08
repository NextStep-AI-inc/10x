import Testing
@testable import TenXApp

@Test func sourcePresentationPreservesIndentationAsUntokenizedSource() {
    let source = SourcePresentation(
        language: "swift",
        text: "  let count = 12 // rows")

    #expect(source.lines.count == 1)
    #expect(source.lines[0].plainText == "  let count = 12 // rows")
    #expect(source.lines[0].spans == [
        SourceSpan(text: "  let count = 12 // rows", role: .plain),
    ])
}

@Test func unknownLanguageKeepsReadablePlainSource() {
    let source = SourcePresentation(
        language: "future-lang",
        text: "alpha  beta")

    #expect(source.lines[0].plainText == "alpha  beta")
    #expect(source.lines[0].spans == [
        SourceSpan(text: "alpha  beta", role: .plain),
    ])
}

@Test func sourcePresentationPreservesEmptyAndTrailingLines() {
    let source = SourcePresentation(language: "swift", text: "let a = 1\n\n")

    #expect(source.lines.map(\.number) == [1, 2, 3])
    #expect(source.lines.map(\.plainText) == ["let a = 1", "", ""])
}

@Test func numericHighlightingStopsBeforeIdentifierText() {
    let spans = SourceTokenizer.spans(
        "12bar 0xff 0b1010 1.5e-2",
        language: "swift")

    #expect(spans == [
        SourceSpan(text: "12", role: .number),
        SourceSpan(text: "bar ", role: .plain),
        SourceSpan(text: "0xff", role: .number),
        SourceSpan(text: " ", role: .plain),
        SourceSpan(text: "0b1010", role: .number),
        SourceSpan(text: " ", role: .plain),
        SourceSpan(text: "1.5e-2", role: .number),
    ])
}
