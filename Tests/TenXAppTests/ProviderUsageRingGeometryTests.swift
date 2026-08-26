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

@Test func constrainedUsageRingMetricsScaleTheCoreAndRetainEveryLimit() {
    let metrics = ProviderUsageRingGeometry.metrics(limitCount: 12, outerDiameter: 44)
    let scaledCore = ProviderUsageRingGeometry.coreDiameter(for: 44)

    #expect(metrics.count == 12)
    #expect(abs(scaledCore - 44 / 3) < 0.001)
    #expect(metrics.first.map { ($0.diameter - $0.lineWidth) / 2 > scaledCore / 2 } ?? false)
    #expect(metrics.last.map { ($0.diameter + $0.lineWidth) / 2 <= 22 } ?? false)
}

@Test func backgroundAccountRingMetricsScaleEveryLimitWithTheSmallerWheel() {
    let geometry = ProviderAccountStackGeometry(
        accountIDs: ["foreground", "background"],
        foregroundAccountID: "foreground",
        wheelDiameter: 54)
    let backgroundDiameter = geometry.items.first(where: {
        $0.accountID == "background"
    })?.visualDiameter ?? 0
    let metrics = ProviderUsageRingGeometry.metrics(
        limitCount: 5,
        outerDiameter: backgroundDiameter)

    #expect(backgroundDiameter < 54)
    #expect(metrics.count == 5)
    #expect(metrics.last.map {
        ($0.diameter + $0.lineWidth) / 2 <= backgroundDiameter / 2
    } ?? false)
}

@Test func providerUsageWheelShowsZeroGeneratingSessionsInItsCenter() {
    #expect(ProviderUsageWheelActivityPresentation.countText(activeCount: 0) == "0")
}

@Test func providerUsageWheelShowsFiveGeneratingSessionsInItsCenter() {
    #expect(ProviderUsageWheelActivityPresentation.countText(activeCount: 5) == "5")
}
}
