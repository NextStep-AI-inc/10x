import Testing
@testable import TenXApp

@Suite struct ProgressiveRevealTests {
    @Test func progressiveRevealAddsOnlyOneFinitePage() {
        var reveal = ProgressiveReveal(initialLimit: 10, pageSize: 100)
        #expect(reveal.visibleCount(total: 10_000) == 10)
        #expect(reveal.nextPageCount(total: 10_000) == 100)
        reveal.revealNextPage(total: 10_000)
        #expect(reveal.visibleCount(total: 10_000) == 110)
    }

    @Test func progressiveRevealClampsTheFinalPageAndCollapses() {
        var reveal = ProgressiveReveal(initialLimit: 8, pageSize: 50)
        reveal.revealNextPage(total: 30)
        #expect(reveal.visibleCount(total: 30) == 30)
        #expect(!reveal.canRevealMore(total: 30))
        reveal.collapse()
        #expect(reveal.visibleCount(total: 30) == 8)
    }

    @Test func progressiveRevealClampsInvalidTotals() {
        let reveal = ProgressiveReveal(initialLimit: 10, pageSize: 20)
        #expect(reveal.visibleCount(total: -5) == 0)
        #expect(reveal.remainingCount(total: -5) == 0)
    }

    @Test func revealCopyUsesSingularNounsForTheFinalItem() {
        #expect(ProgressiveRevealCopy.label(count: 1, noun: "characters") == "Show 1 more character")
        #expect(ProgressiveRevealCopy.label(count: 1, noun: "diff line characters") == "Show 1 more diff line character")
        #expect(ProgressiveRevealCopy.label(count: 2, noun: "characters") == "Show 2 more characters")
        #expect(ProgressiveRevealCopy.label(count: 4_000, noun: "characters") == "Show 4,000 more characters")
    }
}
