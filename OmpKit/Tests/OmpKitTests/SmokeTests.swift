import Testing
@testable import OmpKit

@Test func packageBuilds() {
    #expect(OmpKitInfo.testedOmpVersion == "18.0.4")
}
