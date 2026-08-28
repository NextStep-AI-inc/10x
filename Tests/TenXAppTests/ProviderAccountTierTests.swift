import Foundation
import Testing
@testable import TenXApp

private func accountSnapshot() throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data("""
    {"generatedAt":1,"reports":[
      {"provider":"anthropic","fetchedAt":1,"limits":[],"metadata":{"email":"a@example.com","accountId":"acc-1"}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """.utf8))
}

@Suite struct ProviderAccountTierTests {

@Test func compatibleHelloSelectsTheExtensionTier() throws {
    let tier = ProviderAccountTier.detect(
        snapshot: try accountSnapshot(),
        extensionHello: ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion))

    #expect(tier == .extensionBacked)
}

@Test func missingHelloFallsBackToStockOMP() throws {
    #expect(ProviderAccountTier.detect(snapshot: try accountSnapshot(), extensionHello: nil) == .stockOMP)
}

@Test func unknownContractVersionFallsBackToStockOMP() throws {
    let tier = ProviderAccountTier.detect(
        snapshot: try accountSnapshot(),
        extensionHello: ProviderExtensionHello(contractVersion: ProviderAccountTier.contractVersion + 1))

    #expect(tier == .stockOMP)
}

@Test func snapshotWithoutPerAccountMetadataIsProviderOnly() throws {
    let snapshot = try JSONDecoder().decode(OmpUsageSnapshot.self, from: Data("""
    {"generatedAt":1,"reports":[
      {"provider":"cursor","fetchedAt":1,"limits":[],"metadata":{}}
    ],"accountsWithoutUsage":[],"disabledCredentials":[]}
    """.utf8))

    #expect(ProviderAccountTier.detect(snapshot: snapshot, extensionHello: nil) == .providerOnly)
}

}
