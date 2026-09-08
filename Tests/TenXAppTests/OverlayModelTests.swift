import ComputerKit
import XCTest
@testable import TenXApp

final class OverlayModelTests: XCTestCase {
    func test_claim_addsOverlay() {
        let model = OverlayModel()
        model.apply(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "100,100 800x600"))
        XCTAssertEqual(model.overlays[10]?.app, "Safari")
        XCTAssertEqual(model.overlays[10]?.frame, CGRect(x: 100, y: 100, width: 800, height: 600))
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
}
