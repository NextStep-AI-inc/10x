import Foundation
import Testing
@testable import TenXApp

private func noticeDescriptor(
    text: String = "Consider addressing the user's question directly."
) -> HarnessMessageDescriptor {
    HarnessMessageDescriptor(
        role: "custom",
        customType: "advisor",
        byteCount: text.count,
        text: text)
}

private func tempCacheURL() -> URL {
    URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("harness-summarizer-\(UUID().uuidString)")
        .appendingPathComponent("summaries.json")
}

@Test func summarizerReturnsTheLastStdoutLine() async {
    let summarizer = HarnessNoticeSummarizer(
        resolveModel: { "cursor/smol" },
        cacheURL: tempCacheURL(),
        run: { args in
            #expect(args.contains("-p"))
            #expect(args.contains("--no-session"))
            #expect(args.contains("--no-tools"))
            #expect(args.contains("cursor/smol"))
            return Data("Working...\nAn advisor note suggesting a direct answer.\n".utf8)
        })

    let summary = await summarizer.summarize(noticeDescriptor())

    #expect(summary == "An advisor note suggesting a direct answer.")
}

@Test func summarizerSkipsTheRunWhenNoModelResolves() async {
    let runCount = RunCount()
    let summarizer = HarnessNoticeSummarizer(
        resolveModel: { nil },
        cacheURL: tempCacheURL(),
        run: { _ in
            await runCount.increment()
            return Data()
        })

    let summary = await summarizer.summarize(noticeDescriptor())

    #expect(summary == nil)
    #expect(await runCount.value == 0)
}

@Test func summarizerCachesByContentHashAcrossInstances() async {
    let cacheURL = tempCacheURL()
    let runCount = RunCount()
    let make: () -> HarnessNoticeSummarizer = {
        HarnessNoticeSummarizer(
            resolveModel: { "cursor/smol" },
            cacheURL: cacheURL,
            run: { _ in
                await runCount.increment()
                return Data("cached summary\n".utf8)
            })
    }

    let first = await make().summarize(noticeDescriptor())
    let second = await make().summarize(noticeDescriptor())

    #expect(first == "cached summary")
    #expect(second == "cached summary")
    #expect(await runCount.value == 1)
}

@Test func summarizerReturnsNilWhenTheRunFails() async {
    struct RunError: Error {}
    let summarizer = HarnessNoticeSummarizer(
        resolveModel: { "cursor/smol" },
        cacheURL: tempCacheURL(),
        run: { _ in throw RunError() })

    #expect(await summarizer.summarize(noticeDescriptor()) == nil)
}

private actor RunCount {
    private(set) var value = 0
    func increment() { value += 1 }
}
