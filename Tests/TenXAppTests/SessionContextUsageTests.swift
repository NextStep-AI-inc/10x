import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite struct SessionContextUsageTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func decodesCurrentOMPUsageAndDerivesItsDisplayValues() throws {
        let usage = try #require(SessionContextUsage(value: .object([
            "tokens": .int(2_000),
            "contextWindow": .int(200_000),
            "percent": .double(1),
        ]), updatedAt: date))

        #expect(usage.tokens == 2_000)
        #expect(usage.contextWindow == 200_000)
        #expect(usage.percent == 1)
        #expect(usage.remainingTokens == 198_000)
        #expect(usage.fillFraction == 0.01)
        #expect(usage.updatedAt == date)
    }

    @Test func usageSupportsOverflowWithoutOverflowingRemainingTokens() throws {
        let usage = try #require(SessionContextUsage(value: .object([
            "tokens": .int(Int.max),
            "contextWindow": .int(100),
            "percent": .double(9_999),
        ]), updatedAt: date))

        #expect(usage.percent > 100)
        #expect(usage.remainingTokens == 0)
        #expect(usage.fillFraction == 1)
    }

    @Test(arguments: [
        JSONValue.object(["tokens": .int(-1), "contextWindow": .int(100), "percent": .int(0)]),
        JSONValue.object(["tokens": .int(1), "contextWindow": .int(0), "percent": .int(0)]),
        JSONValue.object(["tokens": .double(.infinity), "contextWindow": .int(100), "percent": .int(0)]),
        JSONValue.object(["tokens": .int(1), "contextWindow": .int(100), "percent": .double(.nan)]),
        JSONValue.object(["tokens": .int(1), "contextWindow": .double(Double.greatestFiniteMagnitude), "percent": .int(0)]),
        JSONValue.object(["tokens": .int(1), "percent": .int(1)]),
    ])
    func usageRejectsInvalidOrUnknownCapacity(_ value: JSONValue) {
        #expect(SessionContextUsage(value: value, updatedAt: date) == nil)
    }

    @Test func parsesRealOMPContextReportAndMapsPresentationLabels() throws {
        let report = """
        Context window: 200000 tokens (33% used)
          System prompt    [██░░] 6%  12000 tokens
          System tools     [██░░] 9%  18000 tokens
          System context   [█░░░] 4%  8000 tokens
          Skills           [█░░░] 2%  4000 tokens
          Messages         [██░░] 12%  24000 tokens
          Auto-compact buf [██░░] 10%  20000 tokens
          Free             [████] 57%  114000 tokens
        Snapcompact (estimated wire savings):
          System prompt: 12000 text tokens → 1 frame ≈ 1500 tokens (saves ~10500)
        """

        let breakdown = try #require(SessionContextBreakdown(report: report, updatedAt: date))
        #expect(breakdown.contextWindow == 200_000)
        #expect(breakdown.usedTokens == 66_000)
        #expect(breakdown.autoCompactBufferTokens == 20_000)
        #expect(breakdown.updatedAt == date)
        #expect(breakdown.categories.map(\.label) == [
            "Conversation", "System instructions", "Tool definitions", "Project context", "Skills",
        ])
        #expect(breakdown.categories.map(\.tokens) == [24_000, 12_000, 18_000, 8_000, 4_000])
        #expect(breakdown.categories.map(\.id) == [
            "messages", "systemPrompt", "systemTools", "systemContext", "skills",
        ])
    }

    @Test func omittedZeroCategoriesRemainPresent() throws {
        let breakdown = try #require(SessionContextBreakdown(report: """
        Context window: 1000 tokens (10% used)
          Messages         [██░░] 10%  100 tokens
          Free             [████] 90%  900 tokens
        """, updatedAt: date))

        #expect(breakdown.categories.map(\.tokens) == [100, 0, 0, 0, 0])
        #expect(breakdown.autoCompactBufferTokens == 0)
    }

    @Test func parsesThemeEscapeSequencesUsedInsideOMPProgressBars() throws {
        let breakdown = try #require(SessionContextBreakdown(report: """
        Context window: 1000 tokens (10% used)
          Messages         [\u{001B}[38;2;0;255;255m██\u{001B}[39m░░] 10%  100 tokens
          Free             [████] 90%  900 tokens
        """, updatedAt: date))

        #expect(breakdown.usedTokens == 100)
    }

    @Test func usedTokensMayExceedTheContextWindow() throws {
        let breakdown = try #require(SessionContextBreakdown(report: """
        Context window: 100 tokens (125% used)
          Messages         [████] 100%  125 tokens
        """, updatedAt: date))

        #expect(breakdown.usedTokens == 125)
    }

    @Test func rejectsAReportWhoseCategoryTotalOverflows() {
        let report = """
        Context window: 100 tokens (101% used)
          Messages         [████] 100%  9223372036854775807 tokens
          Skills           [█░░░] 1%  1 tokens
        """

        #expect(SessionContextBreakdown(report: report, updatedAt: date) == nil)
    }

    @Test(arguments: [
        "Context usage is unavailable: no model is selected for this session.",
        "Context window: 1000 tokens (10% used)\n  Memory           [██░░] 10%  100 tokens",
        "Context window: 1000 tokens (10% used)\n  Messages         [██░░] 10%  tokens",
        "Context window: 1000 tokens (10% used)\n  Messages         [██░░] 10%  100 tokens\nUnexpected",
        "Context window: 1000 tokens (10% used)\n  Messages         [██░░] 10%  100 tokens\n  Messages         [██░░] 10%  100 tokens",
        "Context window: 1000 tokens (10% used)\n  Messages         [██░░] 10%  9223372036854775808 tokens",
    ])
    func rejectsUnknownOrMalformedReports(_ report: String) {
        #expect(SessionContextBreakdown(report: report, updatedAt: date) == nil)
    }
}
