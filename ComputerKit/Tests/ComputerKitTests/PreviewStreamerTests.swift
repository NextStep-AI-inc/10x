import XCTest
@testable import ComputerKit

final class PreviewStreamerTests: XCTestCase {
    func test_actionTriggersImmediateFrame() {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([9, 9, 9])
        var frames: [SupervisionEvent] = []
        let streamer = PreviewStreamer(engine: engine, interval: 60) { event in frames.append(event) }
        defer { streamer.setActive(session: nil, windowID: nil) }
        streamer.actionOccurred(session: SessionID(raw: 1), windowID: 10)
        XCTAssertEqual(frames, [.screenshotTaken(session: 1, windowID: 10, pngBase64: Data([9, 9, 9]).base64EncodedString())])
    }

    func test_heartbeatEmitsWhileControlling_thenStops() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1])
        var frameCount = 0
        let secondFrame = expectation(description: "second heartbeat frame")
        var streamer: PreviewStreamer!
        streamer = PreviewStreamer(engine: engine, interval: 0.05) { _ in
            frameCount += 1
            guard frameCount == 2 else { return }
            streamer.setActive(session: nil, windowID: nil)
            secondFrame.fulfill()
        }
        defer { streamer.setActive(session: nil, windowID: nil) }

        streamer.setActive(session: SessionID(raw: 1), windowID: 10)
        wait(for: [secondFrame], timeout: 1.0)
        XCTAssertEqual(frameCount, 2)

        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(frameCount, 2)
    }

    func test_stopPreviewForSession_doesNotStopOtherSession() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1])
        var frameCount = 0
        let streamer = PreviewStreamer(engine: engine, interval: 0.05) { _ in frameCount += 1 }
        defer { streamer.setActive(session: nil, windowID: nil) }

        streamer.setActive(session: SessionID(raw: 1), windowID: 10)

        let beforeStop = expectation(description: "heartbeat before stop")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) { beforeStop.fulfill() }
        wait(for: [beforeStop], timeout: 1.0)
        let countAfterHeartbeat = frameCount
        XCTAssertGreaterThanOrEqual(countAfterHeartbeat, 1)

        streamer.stopPreview(for: SessionID(raw: 2))

        let afterStop = expectation(description: "heartbeat continues after unrelated stop")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) { afterStop.fulfill() }
        wait(for: [afterStop], timeout: 1.0)
        XCTAssertGreaterThan(frameCount, countAfterHeartbeat)
    }

    func test_windowGoneStopsHeartbeat() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1])
        engine.screenshotError = ComputerError("window_gone: 10")
        var frameCount = 0
        let streamer = PreviewStreamer(engine: engine, interval: 0.05) { _ in frameCount += 1 }
        defer { streamer.setActive(session: nil, windowID: nil) }

        streamer.setActive(session: SessionID(raw: 1), windowID: 10)

        let settled = expectation(description: "window_gone clears active")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { settled.fulfill() }
        wait(for: [settled], timeout: 1.0)

        let countAfterGone = frameCount
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(frameCount, countAfterGone)
    }
}
