import Testing
@testable import TenXApp

@Test func providerUsageNormalizesPercentagesForRendering() {
    let over = ProviderUsageLimit(id: "over", label: "Weekly", percentage: 140, resetWindow: "Mon")
    let under = ProviderUsageLimit(id: "under", label: "Spark", percentage: -8, resetWindow: "Thu")

    #expect(over.normalizedFraction == 1)
    #expect(under.normalizedFraction == 0)
}

@Test func providerUsageToneMakesOnlyLowAndExhaustedLimitsAttentionStates() {
    let healthy = ProviderUsageLimit(id: "healthy", label: "5 hours", percentage: 64, resetWindow: "2h 14m")
    let low = ProviderUsageLimit(id: "low", label: "Spark", percentage: 18, resetWindow: "Thu")
    let exhausted = ProviderUsageLimit(id: "empty", label: "Weekly", percentage: 0, resetWindow: "Mon")

    #expect(healthy.tone == .standard)
    #expect(low.tone == .warning)
    #expect(exhausted.tone == .exhausted)
}
