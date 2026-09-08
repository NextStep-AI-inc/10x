import XCTest
@testable import TenXApp

final class ComputerActivityTrackerTests: XCTestCase {
    func test_ignoresNonComputerTools() {
        var tracker = ComputerActivityTracker()
        XCTAssertFalse(tracker.toolStarted(name: "bash", input: nil))
        XCTAssertFalse(tracker.isActive)
    }

    func test_claim_marksActiveWithWindow() {
        var tracker = ComputerActivityTracker()
        XCTAssertTrue(tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10]))
        XCTAssertTrue(tracker.isActive)
        XCTAssertEqual(tracker.claimedWindowIDs, [10])
    }

    func test_launch_claimsResultWindow() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_launch", input: ["app": "Safari"])
        tracker.toolCompleted(name: "mcp__tenx-computer_computer_launch", claimedWindowID: 11)
        XCTAssertEqual(tracker.claimedWindowIDs, [11])
    }

    func test_release_removesWindow() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_release", input: ["window_id": 10])
        XCTAssertFalse(tracker.isActive)
    }

    func test_act_marksControlling() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_act", input: ["window_id": 10, "action": "click"])
        XCTAssertEqual(tracker.phase, .controlling)
    }

    func test_readOnlyTools_keepReadyPhase() {
        var tracker = ComputerActivityTracker()
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_claim", input: ["window_id": 10])
        _ = tracker.toolStarted(name: "mcp__tenx-computer_computer_screenshot", input: ["window_id": 10])
        XCTAssertEqual(tracker.phase, .ready)
    }
}
