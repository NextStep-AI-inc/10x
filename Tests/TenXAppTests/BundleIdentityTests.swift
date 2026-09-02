import Foundation
import Testing
@testable import TenXApp

@Test func bundleIdentifierIsOwnedByNextStep() {
    let identifier = Bundle.main.bundleIdentifier
    #expect(identifier == "com.nextstep.tenx")
}

@Test func versionKeysResolveToConcreteValues() {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    #expect(short?.isEmpty == false)
    #expect(build?.isEmpty == false)
    #expect(short?.contains("$") == false)
    #expect(build?.contains("$") == false)
}
