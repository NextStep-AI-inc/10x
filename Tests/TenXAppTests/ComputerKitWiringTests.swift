import ComputerKit
import XCTest

final class ComputerKitWiringTests: XCTestCase {
    func test_computerKitIsLinked() {
        // SupervisionEvent is the type the app's supervision client decodes.
        let event = SupervisionEvent.stopped(reason: "wiring check", session: nil)
        XCTAssertEqual(event, .stopped(reason: "wiring check", session: nil))
    }
}
