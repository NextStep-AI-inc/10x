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

    func test_decodeUnknownType_throws() {
        XCTAssertThrowsError(try SupervisionEvent(jsonLine: #"{"type":"futureEvent"}"#))
    }

    func test_decodeMissingRequiredField_throws() {
        XCTAssertThrowsError(try SupervisionEvent(jsonLine: #"{"type":"stopped"}"#))
    }

    func test_decodeExtraUnknownField_stillDecodes() throws {
        let decoded = try SupervisionEvent(jsonLine: #"{"type":"stopped","reason":"shutdown","extraField":"value"}"#)
        XCTAssertEqual(decoded, .stopped(reason: "shutdown"))
    }

    func test_decodeWindowClaimed_pinsCamelCaseKeys() throws {
        let json = #"{"type":"windowClaimed","session":1,"harness":"omp","windowID":10,"app":"Safari","title":"Apple","bounds":"0,0 800x600"}"#
        let decoded = try SupervisionEvent(jsonLine: json)
        XCTAssertEqual(decoded, .windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
    }

    func test_screenshotTaken_largePayloadRoundTrip() throws {
        let payload = String(repeating: "A", count: 100 * 1024)
        let event = SupervisionEvent.screenshotTaken(session: 1, windowID: 10, pngBase64: payload)
        let line = try event.jsonLine()
        let decoded = try SupervisionEvent(jsonLine: line)
        XCTAssertEqual(decoded, event)
    }
}
