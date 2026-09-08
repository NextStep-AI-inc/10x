import Foundation
import Testing
@testable import TenXApp

private struct PinHashCase: Decodable {
    struct Input: Decodable {
        let provider: String
        let accountId: String?
        let email: String?
        let orgId: String?
        let projectId: String?
    }

    let input: Input
    let hash: String?
}

@Test func accountRefMatchesOmpCredentialPinHash() throws {
    let url = try #require(Bundle(for: SnapshotToken.self).url(
        forResource: "credential-pin-hashes",
        withExtension: "json",
        subdirectory: "Fixtures"))
    let cases = try JSONDecoder().decode([PinHashCase].self, from: Data(contentsOf: url))
    #expect(cases.count >= 8)

    for testCase in cases {
        let actual = ProviderAccountRef.make(
            providerID: testCase.input.provider,
            accountID: testCase.input.accountId,
            email: testCase.input.email,
            orgID: testCase.input.orgId,
            projectID: testCase.input.projectId)
        #expect(actual == testCase.hash, "mismatch for \(testCase.input.provider)")
    }
}
