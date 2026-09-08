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
        let decoded = try SupervisionEvent(jsonLine: try event.jsonLine())
        XCTAssertEqual(decoded, .action(session: 2, windowID: 10, kind: "click", x: 50, y: 60))
    }

    func test_actionEventNullCoordinatesForType() throws {
        let event = SupervisionEvent.action(session: 1, windowID: 10, kind: "type", x: nil, y: nil)
        let line = try event.jsonLine()
        XCTAssertTrue(line.contains("\"x\":null"))
        let decoded = try SupervisionEvent(jsonLine: line)
        XCTAssertEqual(decoded, event)
    }

    func test_screenshotTaken_carriesBase64FrameAndDims() throws {
        let event = SupervisionEvent.screenshotTaken(session: 1, windowID: 10, pngBase64: "aGk=", width: 100, height: 100, scale: 2)
        let decoded = try SupervisionEvent(jsonLine: try event.jsonLine())
        XCTAssertEqual(decoded, event)
    }

    func test_sessionStarted_carriesLabelAndPID() throws {
        let event = SupervisionEvent.sessionStarted(session: 1, harness: "omp", label: "Fix login", pid: 1234)
        let decoded = try SupervisionEvent(jsonLine: try event.jsonLine())
        XCTAssertEqual(decoded, event)
    }

    /// Wire freeze: absent optionals encode as explicit null, never omitted keys.
    func test_sessionStarted_nilLabelAndPID_encodeAsNull() throws {
        let event = SupervisionEvent.sessionStarted(session: 1, harness: "omp", label: nil, pid: nil)
        let line = try event.jsonLine()
        let object = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        XCTAssertEqual(object["label"], .null)
        XCTAssertEqual(object["pid"], .null)
        let decoded = try SupervisionEvent(jsonLine: line)
        XCTAssertEqual(decoded, event)
    }

    func test_permissionsEventRoundTrip() throws {
        let event = SupervisionEvent.permissions(screenRecording: true, accessibility: false)
        let decoded = try SupervisionEvent(jsonLine: try event.jsonLine())
        XCTAssertEqual(decoded, event)
    }

    func test_stoppedCarriesSession() throws {
        let event = SupervisionEvent.stopped(reason: "session 1 stopped", session: 1)
        let decoded = try SupervisionEvent(jsonLine: try event.jsonLine())
        XCTAssertEqual(decoded, event)
    }

    func test_decodeUnknownType_throws() {
        XCTAssertThrowsError(try SupervisionEvent(jsonLine: #"{"type":"futureEvent"}"#))
    }

    func test_decodeMissingRequiredField_throws() {
        XCTAssertThrowsError(try SupervisionEvent(jsonLine: #"{"type":"stopped"}"#))
    }

    func test_decodeExtraUnknownField_stillDecodes() throws {
        let decoded = try SupervisionEvent(jsonLine: #"{"type":"stopped","reason":"shutdown","extraField":"value"}"#)
        XCTAssertEqual(decoded, .stopped(reason: "shutdown", session: nil))
    }

    func test_decodeWindowClaimed_pinsCamelCaseKeys() throws {
        let json = #"{"type":"windowClaimed","session":1,"harness":"omp","windowID":10,"app":"Safari","title":"Apple","bounds":"0,0 800x600"}"#
        let decoded = try SupervisionEvent(jsonLine: json)
        XCTAssertEqual(decoded, .windowClaimed(session: 1, harness: "omp", windowID: 10, app: "Safari", title: "Apple", bounds: "0,0 800x600"))
    }

    func test_screenshotTaken_largePayloadRoundTrip() throws {
        let payload = String(repeating: "A", count: 100 * 1024)
        let event = SupervisionEvent.screenshotTaken(session: 1, windowID: 10, pngBase64: payload, width: 800, height: 600, scale: 2)
        let line = try event.jsonLine()
        let decoded = try SupervisionEvent(jsonLine: line)
        XCTAssertEqual(decoded, event)
    }
}
