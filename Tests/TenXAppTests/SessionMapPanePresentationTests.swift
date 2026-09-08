import Testing
@testable import TenXApp

@Test func sessionMapUsesDrawerBelowDockThreshold() {
    #expect(SessionMapPanePresentation.resolve(
        windowWidth: 760,
        requestedPaneWidth: 440) == .drawer(width: 440))
    #expect(SessionMapPanePresentation.resolve(
        windowWidth: 1180,
        requestedPaneWidth: 900) == .docked(width: 590))
    #expect(SessionMapPanePresentation.resolve(
        windowWidth: 1440,
        requestedPaneWidth: 100) == .docked(width: 320))
}
