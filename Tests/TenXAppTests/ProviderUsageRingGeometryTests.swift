import Testing
@testable import TenXApp

@Suite struct ProviderUsageRingGeometryTests {
@Test(arguments: [0, 1, 2, 3, 12])
func providerUsageRingMetricsScaleWithoutDroppingRings(limitCount: Int) {
    let metrics = ProviderUsageRingGeometry.metrics(limitCount: limitCount)

    #expect(ProviderUsageRingGeometry.diameter == 54)
    #expect(ProviderUsageRingGeometry.coreDiameter == 18)
    #expect(metrics.count == max(limitCount, 0))
    #expect(limitCount != 0 || metrics.isEmpty)
    #expect(metrics.allSatisfy { $0.lineWidth > 0 })
    #expect(zip(metrics, metrics.dropFirst()).allSatisfy { $0.diameter < $1.diameter })
    #expect(metrics.first.map { ($0.diameter - $0.lineWidth) / 2 > ProviderUsageRingGeometry.coreDiameter / 2 } ?? true)
    #expect(metrics.last.map { ($0.diameter + $0.lineWidth) / 2 <= ProviderUsageRingGeometry.diameter / 2 } ?? true)
}

@Test func providerUsageRingMetricsRetainDenseLimits() {
    #expect(ProviderUsageRingGeometry.metrics(limitCount: 12).count == 12)
}
}
