import AppKit
import Testing
@testable import TenXApp

@MainActor @Test func probeWindowOrdersBehindWithoutTakingFocus() throws {
    let previouslyKey = NSApp.keyWindow
    let probe = AgentDesktopProbeWindow()

    let target = try probe.open()

    #expect(!target.windowID.isEmpty)
    #expect(!probe.window.isKeyWindow)
    #expect(NSApp.keyWindow === previouslyKey)
    probe.close()
}
