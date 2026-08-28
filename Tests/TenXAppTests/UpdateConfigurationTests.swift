import Foundation
import Testing
@testable import TenXApp

@Test func updateFeedPointsAtTheNextStepReleaseFeed() {
    let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String

    #expect(feed == "https://github.com/NextStep-AI-inc/10x/releases/latest/download/appcast.xml")
}

@Test func updatePublicKeyIsPresentAndDecodable() throws {
    let key = try #require(
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    let decoded = try #require(Data(base64Encoded: key))

    #expect(decoded.count == 32)
}

@Test func sparkleNeverSchedulesItsOwnChecksOrInstalls() {
    let automaticChecks = Bundle.main.object(
        forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool
    let automaticInstalls = Bundle.main.object(
        forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool

    #expect(automaticChecks == false)
    #expect(automaticInstalls == false)
}
