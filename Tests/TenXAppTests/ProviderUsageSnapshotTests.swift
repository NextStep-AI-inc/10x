import Foundation
import Testing
@testable import TenXApp

let usageSnapshotFixtureData = Data(#"""
    {
      "generatedAt":1787675745954,
      "reports":[{
        "provider":"cursor",
        "fetchedAt":1787675745599,
        "limits":[
          {"id":"cursor:models","label":"Cursor Models","scope":{"provider":"cursor","windowId":"monthly"},"window":{"id":"monthly","label":"Monthly","resetsAt":1788061624000},"amount":{"usedFraction":0.499,"unit":"percent"},"status":"ok"},
          {"id":"cursor:requests","label":"Requests","scope":{"provider":"cursor"},"amount":{"used":4,"unit":"requests"}}
        ],
        "metadata":{"email":"tanner@example.com"},
        "futureField":{"ignored":true}
      }],
      "accountsWithoutUsage":[{"provider":"github-copilot","email":"work@example.com"}],
      "disabledCredentials":[{"id":2,"provider":"anthropic","type":"oauth","cause":"refresh failed","email":"old@example.com","disabledAtMs":1787616419000}],
      "capacity":{}
    }
    """#.utf8)

func usageSnapshotFixture() throws -> OmpUsageSnapshot {
    try JSONDecoder().decode(OmpUsageSnapshot.self, from: usageSnapshotFixtureData)
}

@Test func usageSnapshotDecodesTheNarrowOMPContract() throws {
    let snapshot = try usageSnapshotFixture()

    #expect(snapshot.reports[0].limits.count == 2)
    #expect(snapshot.reports[0].metadata?["email"]?.stringValue == "tanner@example.com")
    #expect(snapshot.accountsWithoutUsage[0].provider == "github-copilot")
    #expect(snapshot.disabledCredentials[0].provider == "anthropic")
}
