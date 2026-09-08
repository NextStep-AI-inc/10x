import ComputerKit
import XCTest
@testable import TenXApp

final class SupervisionClientTests: XCTestCase {
    func makeClient() -> SupervisionClient {
        SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock")
    }

    func test_sessionStarted_addsSessionGroupedByHarness() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
        XCTAssertEqual(client.sessions[1]?.harness, "omp")
        XCTAssertEqual(client.sessions[2]?.harness, "Cursor")
    }

    func test_windowClaimed_attachesWindowToSession() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        XCTAssertEqual(client.sessions[1]?.windows.first?.windowID, 10)
        XCTAssertEqual(client.sessions[1]?.windows.first?.app, "Safari")
    }

    func test_windowClaimed_isIdempotent() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        XCTAssertEqual(client.sessions[1]?.windows.count, 1)
    }

    func test_windowReleased_removesWindow() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.windowReleased(session: 1, windowID: 10, reason: "released"))
        XCTAssertEqual(client.sessions[1]?.windows.count, 0)
    }

    func test_screenshotTaken_storesLatestFramePerWindow() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([1, 2]).base64EncodedString(), width: 100, height: 100, scale: 2))
        client.apply(.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([3, 4]).base64EncodedString(), width: 100, height: 100, scale: 2))
        XCTAssertEqual(client.frames[10], Data([3, 4]))
    }

    func test_action_updatesLastAction() {
        let client = makeClient()
        client.apply(.action(session: 1, windowID: 10, kind: "click", x: 50, y: 60))
        XCTAssertEqual(client.lastAction?.windowID, 10)
        XCTAssertEqual(client.lastAction?.kind, "click")
    }

    func test_statusChanged_updatesSessionStatus() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.statusChanged(session: 1, status: "Running tests…"))
        XCTAssertEqual(client.sessions[1]?.status, "Running tests…")
    }

    func test_stopped_clearsEverything() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.stopped(reason: "global shut-off", session: nil))
        XCTAssertTrue(client.sessions.isEmpty)
        XCTAssertTrue(client.frames.isEmpty)
    }

    func test_stoppedWithSession_removesOnlyThatSession() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
        client.apply(.stopped(reason: "session 1 stopped", session: 1))
        XCTAssertNil(client.sessions[1])
        XCTAssertNotNil(client.sessions[2])
    }

    func test_permissions_storesLatest() {
        let client = makeClient()
        XCTAssertNil(client.permissions)
        client.apply(.permissions(screenRecording: true, accessibility: false))
        XCTAssertEqual(client.permissions?.screenRecording, true)
        XCTAssertEqual(client.permissions?.accessibility, false)
    }

    func test_disconnect_clearsPermissions() {
        let client = makeClient()
        client.apply(.permissions(screenRecording: true, accessibility: true))
        client.resetConnectionState()
        XCTAssertFalse(client.isConnected)
        XCTAssertNil(client.permissions)
    }

    func test_disconnect_clearsSessionsAndFrames() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        client.apply(.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([1, 2]).base64EncodedString(), width: 100, height: 100, scale: 2))
        client.apply(.action(session: 1, windowID: 10, kind: "click", x: 50, y: 60))
        client.resetConnectionState()
        XCTAssertTrue(client.sessions.isEmpty)
        XCTAssertTrue(client.frames.isEmpty)
        XCTAssertNil(client.lastAction)
    }

    func test_sessionEnded_removesOnlyThatSession() {
        let client = makeClient()
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.sessionStarted(session: 2, harness: "Cursor", label: nil, pid: nil))
        client.apply(.sessionEnded(session: 1, harness: "omp"))
        XCTAssertNil(client.sessions[1])
        XCTAssertNotNil(client.sessions[2])
    }

    func test_hasAnyActivity_drivesMenuBarInsertion() {
        let client = makeClient()
        XCTAssertFalse(client.hasAnyActivity)
        client.apply(.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil))
        client.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
        XCTAssertTrue(client.hasAnyActivity)
    }
}
