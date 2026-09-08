import XCTest
@testable import ComputerKit

final class SupervisionEventTests: XCTestCase {
    func test_encodesToSingleLineJSON() throws {
        let event = SupervisionEvent.windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600")
        let line = try event.jsonLine()
        XCTAssertFalse(line.contains("\n"))
        let decoded = try SupervisionEvent(jsonLine: line)
        XCTAssertEqual(decoded, event)
    }

    func test_actionEventCarriesPoint() throws {
        let event = SupervisionEvent.action(session: 2, windowID: 10, kind: "click", x: 50, y: 60)
        let decoded = try SupervisionEvent(jsonLine: event.jsonLine())
        XCTAssertEqual(decoded, .action(session: 2, windowID: 10, kind: "click", x: 50, y: 60))
    }

    func test_screenshotTaken_carriesBase64Frame() throws {
        let event = SupervisionEvent.screenshotTaken(session: 1, windowID: 10, pngBase64: "aGk=")
        let decoded = try SupervisionEvent(jsonLine: event.jsonLine())
        XCTAssertEqual(decoded, .screenshotTaken(session: 1, windowID: 10, pngBase64: "aGk="))
    }
}
