import Dispatch
import Foundation
import Testing
@testable import TenXApp

@Suite struct SourcePageLoaderTests {
    @Test func parserLeavesFencedSourceLinesRawBeforeVisibleLoading() {
        let text = (1...500).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let document = MessageContentParser.parse("""
        ```swift
        \(text)
        ```
        """)

        guard case .source(let source) = document.blocks.first else {
            Issue.record("Expected parsed source")
            return
        }
        #expect(source.lines.count == 500)
        #expect(source.lines[0].spans == [SourceSpan(text: "let value1 = 1", role: .plain)])
        #expect(source.lines[499].spans == [SourceSpan(text: "let value500 = 500", role: .plain)])
    }

    @Test func hiddenSourceLinesNeverReachTheTokenizer() async {
        let source = SourcePresentation(language: "swift", text: sourceText(count: 500))
        let recorder = SourceTokenizationRecorder()
        let loader = await SourcePageLoader(
            initialLines: Array(source.lines.prefix(160)),
            language: source.language,
            tokenize: { text, _ in
                recorder.record(text)
                return [SourceSpan(text: text, role: .plain)]
            })

        #expect(await loader.cachedLineCount == 160)
        #expect(recorder.count == 160)
        #expect(!recorder.contains("let value161 = 161"))
        #expect(!recorder.contains("let value500 = 500"))
    }

    @Test func visibleSourcePagesTokenizeOnlyOneFinitePage() async {
        let source = SourcePresentation(language: "swift", text: sourceText(count: 500))
        let recorder = SourceTokenizationRecorder()
        let loader = await SourcePageLoader(tokenize: { text, _ in
            recorder.record(text)
            return [SourceSpan(text: text, role: .plain)]
        })

        await loader.load(lines: Array(source.lines.prefix(160)), language: source.language)
        #expect(recorder.count == 160)
        await loader.load(lines: Array(source.lines.prefix(320)), language: source.language)

        #expect(await loader.cachedLineCount == 320)
        #expect(recorder.count == 320)
        #expect(!recorder.contains("let value321 = 321"))
    }

    @Test func synchronousPrimeRespectsLineAndCharacterCeilings() async {
        let recorder = SourceTokenizationRecorder()
        let oversized = SourcePresentation(
            language: "swift",
            text: String(repeating: "a", count: 2_049))
        let oversizedLoader = await SourcePageLoader(
            initialLines: oversized.lines,
            language: oversized.language,
            tokenize: { text, _ in
                recorder.record(text)
                return [SourceSpan(text: text, role: .plain)]
            })
        #expect(await oversizedLoader.cachedLineCount == 0)

        let ceiling = String(repeating: "b", count: 2_048)
        let exact = SourcePresentation(
            language: "swift",
            text: (Array(repeating: ceiling, count: 8) + ["deferred"]).joined(separator: "\n"))
        let exactLoader = await SourcePageLoader(
            initialLines: exact.lines,
            language: exact.language,
            tokenize: { text, _ in
                recorder.record(text)
                return [SourceSpan(text: text, role: .plain)]
            })

        #expect(await exactLoader.cachedLineCount == 8)
        #expect(recorder.count == 8)
        #expect(!recorder.contains("deferred"))
    }

    @Test func staleTokenizationCannotPublishAfterSourceReplacement() async {
        let original = SourcePresentation(language: "swift", text: "original")
        let replacement = SourcePresentation(language: "swift", text: "replacement")
        let gate = SourceTokenizationGate()
        let loader = await SourcePageLoader(
            contentID: original.contentID,
            language: original.language,
            tokenize: { text, _ in
                if text == "original" { gate.block() }
                return [SourceSpan(text: text, role: .plain)]
            })
        let oldWork = Task {
            await loader.load(
                lines: original.lines,
                language: original.language,
                contentID: original.contentID)
        }
        defer { gate.resume() }

        #expect(gate.waitForStart())
        await loader.reset(
            contentID: replacement.contentID,
            initialLines: replacement.lines,
            language: replacement.language)
        gate.resume()
        await oldWork.value

        #expect(await loader.spans(
            for: replacement.lines[0],
            contentID: replacement.contentID) == [SourceSpan(text: "replacement", role: .plain)])
    }
}

private final class SourceTokenizationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []

    var count: Int { lock.withLock { texts.count } }

    func contains(_ text: String) -> Bool { lock.withLock { texts.contains(text) } }

    func record(_ text: String) { lock.withLock { texts.append(text) } }
}

private final class SourceTokenizationGate: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let continuation = DispatchSemaphore(value: 0)

    func block() {
        started.signal()
        continuation.wait()
    }

    func waitForStart() -> Bool { started.wait(timeout: .now() + 5) == .success }

    func resume() { continuation.signal() }
}

private func sourceText(count: Int) -> String {
    (1...count).map { "let value\($0) = \($0)" }.joined(separator: "\n")
}
