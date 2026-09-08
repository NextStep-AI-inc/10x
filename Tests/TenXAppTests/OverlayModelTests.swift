import ComputerKit
import XCTest
@testable import TenXApp

final class OverlayModelTests: XCTestCase {
    func test_claim_addsOverlay() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "100,100 800x600"))
        XCTAssertEqual(model.overlays[10]?.identity, "omp · Safari")
        XCTAssertEqual(model.overlays[10]?.frame, CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(model.overlays[10]?.isOnscreen, true)
    }

    func test_claim_prefersSessionLabelForIdentity() {
        let model = OverlayModel()
        model.apply(.sessionStarted(session: 1, harness: "10x", label: "Fix login flow", pid: nil))
        model.apply(.windowClaimed(session: 1, harness: "10x", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        XCTAssertEqual(model.overlays[10]?.identity, "10x · Fix login flow")
    }

    func test_action_movesCursorInWindowRelativePoints() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.action(session: 1, windowID: 10, kind: "click", x: 50, y: 60))
        XCTAssertEqual(model.overlays[10]?.cursor, CGPoint(x: 50, y: 60))
        XCTAssertEqual(model.overlays[10]?.cursorKind, "click")
    }

    func test_status_updatesTag() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.statusChanged(session: 1, status: "Running tests…"))
        XCTAssertEqual(model.overlays[10]?.status, "Running tests…")
    }

    func test_release_removesOverlay() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.windowReleased(session: 1, windowID: 10, reason: "released"))
        XCTAssertTrue(model.overlays.isEmpty)
    }

    func test_boundsParsing_toleratesJunk() {
        XCTAssertNil(OverlayModel.parseBounds("garbage"))
        XCTAssertEqual(OverlayModel.parseBounds("100,100 800x600"), CGRect(x: 100, y: 100, width: 800, height: 600))
    }

    func test_stopped_clearsAll() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.stopped(reason: "global shut-off", session: nil))
        XCTAssertTrue(model.overlays.isEmpty)
    }

    func test_stopped_withSession_clearsOnlyThatSession() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.windowClaimed(session: 2, harness: "cursor", windowID: 20, app: "Finder", title: "", bounds: "0,0 400x300"))
        model.apply(.stopped(reason: "stop_session", session: 1))
        XCTAssertNil(model.overlays[10])
        XCTAssertNotNil(model.overlays[20])
    }

    func test_pollBounds_offscreenWindowHidesButSurvives() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.pollBounds { _ in (CGRect(x: 100, y: 100, width: 800, height: 600), false) }
        XCTAssertEqual(model.overlays[10]?.isOnscreen, false)
        model.pollBounds { _ in (CGRect(x: 110, y: 120, width: 800, height: 600), true) }
        XCTAssertEqual(model.overlays[10]?.isOnscreen, true)
        XCTAssertEqual(model.overlays[10]?.frame, CGRect(x: 110, y: 120, width: 800, height: 600))
    }

    func test_pollBounds_goneWindowRemovedWhileOthersSurvive() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: "100,100 800x600"))
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 20, app: "Finder", title: "", bounds: "0,0 400x300"))
        model.pollBounds { windowID in
            windowID == 10 ? nil : (CGRect(x: 0, y: 0, width: 400, height: 300), true)
        }
        XCTAssertNil(model.overlays[10])
        XCTAssertNotNil(model.overlays[20])
    }
}
