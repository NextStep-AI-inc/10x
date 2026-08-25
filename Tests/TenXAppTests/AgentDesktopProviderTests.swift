import Testing
@testable import TenXApp

@Test func backgroundProviderReportsExplicitlyDegradedCapabilities() async {
    let provider = BackgroundProvider()
    let probe = await provider.probe()

    #expect(probe.availability == .healthy)
    #expect(!probe.capabilities.canIsolate)
    #expect(!probe.capabilities.canMoveWithoutFocus)
    #expect(!probe.capabilities.canCaptureOffscreen)
    #expect(!probe.capabilities.canInputInBackground)
}

@Test func aeroSpaceWorkspaceIDsRejectUnsafeSessionTokens() async {
    let provider = AeroSpaceProvider()

    await #expect(throws: AgentDesktopProviderError.self) {
        try await provider.prepare(sessionToken: "unsafe token;workspace")
    }
}
