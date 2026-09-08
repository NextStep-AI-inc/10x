import XCTest
@testable import ComputerKit

final class PreviewStreamerTests: XCTestCase {
    func test_actionTriggersImmediateFrame() {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([9, 9, 9])
        var frames: [SupervisionEvent] = []
        let streamer = PreviewStreamer(engine: engine, interval: 60) { event in frames.append(event) }
        streamer.actionOccurred(session: SessionID(raw: 1), windowID: 10)
        XCTAssertEqual(frames, [.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([9, 9, 9]).base64EncodedString())])
    }

    func test_heartbeatEmitsWhileControlling_thenStops() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1])
        var frames: [SupervisionEvent] = []
        let streamer = PreviewStreamer(engine: engine, interval: 0.05) { event in frames.append(event) }
        streamer.setActive(session: SessionID(raw: 1), windowID: 10)
        Thread.sleep(forTimeInterval: 0.16)
        streamer.setActive(session: nil, windowID: nil)
        let count = frames.count
        XCTAssertGreaterThanOrEqual(count, 2)
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(frames.count, count) // no frames after stop
    }
}
