import ComputerKit
import XCTest
@testable import TenXApp

@MainActor
final class ComputerUseControllerTests: XCTestCase {
    func makeController() -> ComputerUseController {
        ComputerUseController(supervision: SupervisionClient(socketPath: NSTemporaryDirectory() + "unused-\(UUID().uuidString).sock"))
    }

    func test_toolStream_drivesActivity() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(controller.claimedWindowIDs, [10])
    }

    func test_statusEvent_surfacesAgentStatus() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        controller.applySupervision(.statusChanged(session: 1, status: "Running tests…"))
        XCTAssertEqual(controller.status, "Running tests…")
    }

    func test_statusEvent_fromOtherSession_isIgnored() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        controller.applySupervision(.statusChanged(session: 99, status: "not ours"))
        XCTAssertNil(controller.status)
    }

    func test_stop_withoutDaemonSession_isNoop() async {
        let controller = makeController()
        await controller.stopComputerUse()
        XCTAssertEqual(controller.phase, .off)
    }

    func test_daemonSession_correlatesByClaimedWindow() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.windowClaimed(session: 7, harness: "omp", windowID: 10, app: "Safari", title: "", bounds: ""))
        XCTAssertEqual(controller.daemonSessionID, 7)
    }

    func test_stoppedEvent_clearsActivity() {
        let controller = makeController()
        controller.handleToolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        controller.applySupervision(.stopped(reason: "global shut-off", session: nil))
        XCTAssertEqual(controller.phase, .off)
        XCTAssertEqual(controller.claimedWindowIDs, [])
    }
}
