import XCTest
@testable import ComputerKit

final class SessionRegistryTests: XCTestCase {
    let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
    let terminal = WindowInfo(id: 11, appName: "Terminal", title: "zsh", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 200)

    func test_registerSession_labelsHarnessFromClientName() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "Cursor")
        XCTAssertEqual(registry.session(session)?.harness, "Cursor")
    }

    func test_claim_assignsWindowToSession() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        XCTAssertNoThrow(try registry.claim(safari, for: session))
        XCTAssertEqual(registry.owner(of: safari.id), session)
    }

    func test_claim_rejectsSecondClaimant_andNamesOwner() {
        let registry = SessionRegistry()
        let first = registry.registerSession(clientName: "omp")
        let second = registry.registerSession(clientName: "Cursor")
        try! registry.claim(safari, for: first)
        XCTAssertThrowsError(try registry.claim(safari, for: second)) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "already_claimed: window owned by session 1 (omp)")
        }
    }

    func test_claim_sameSessionTwice_isIdempotent() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        try! registry.claim(safari, for: session)
        XCTAssertNoThrow(try registry.claim(safari, for: session))
        XCTAssertEqual(registry.claimedWindows(for: session).count, 1)
    }

    func test_releaseAll_forSession_leavesOtherSessions() {
        let registry = SessionRegistry()
        let first = registry.registerSession(clientName: "omp")
        let second = registry.registerSession(clientName: "Cursor")
        try! registry.claim(safari, for: first)
        try! registry.claim(terminal, for: second)
        registry.releaseAll(for: first)
        XCTAssertNil(registry.owner(of: safari.id))
        XCTAssertEqual(registry.owner(of: terminal.id), second)
    }

    func test_stopSession_revokesToolsAndReleasesClaims() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        try! registry.claim(safari, for: session)
        registry.stop(session)
        XCTAssertNil(registry.owner(of: safari.id))
        XCTAssertFalse(registry.isActive(session))
    }

    func test_windowClosed_autoReleasesClaim() {
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        try! registry.claim(safari, for: session)
        registry.windowClosed(safari.id)
        XCTAssertNil(registry.owner(of: safari.id))
    }

    func test_stopAll_releasesEverything() {
        let registry = SessionRegistry()
        let first = registry.registerSession(clientName: "omp")
        let second = registry.registerSession(clientName: "Cursor")
        try! registry.claim(safari, for: first)
        try! registry.claim(terminal, for: second)
        registry.stopAll()
        XCTAssertNil(registry.owner(of: safari.id))
        XCTAssertNil(registry.owner(of: terminal.id))
        XCTAssertFalse(registry.isActive(first))
        XCTAssertFalse(registry.isActive(second))
    }
}
