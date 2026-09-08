import XCTest
@testable import ComputerKit

final class ComputerToolsTests: XCTestCase {
    let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 100, y: 100, width: 800, height: 600), pid: 100)

    func makeTools() -> (ComputerTools, FakeEngine, SessionRegistry, SessionID) {
        let engine = FakeEngine()
        engine.windows = [safari]
        engine.screenshotPNG = Data([0x89, 0x50])
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        return (ComputerTools(engine: engine, registry: registry, session: session), engine, registry, session)
    }

    func test_windows_listsUnclaimedWithClaimedBy() throws {
        let (tools, _, _, _) = makeTools()
        let result = try tools.callTool(name: "computer_windows", arguments: .object([:]))
        guard case .text(let text) = result else { return XCTFail("expected text") }
        XCTAssertTrue(text.contains("Safari"))
        XCTAssertTrue(text.contains("\"id\":10") || text.contains("\"id\": 10"))
    }

    func test_claim_thenScreenshot_returnsImageContent() throws {
        let (tools, _, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        let result = try tools.callTool(name: "computer_screenshot", arguments: .object(["window_id": .number(10)]))
        guard case .image(let pngBase64, let text) = result else { return XCTFail("expected image") }
        XCTAssertEqual(Data(base64Encoded: pngBase64), Data([0x89, 0x50]))
        XCTAssertTrue(text.contains("800"))
    }

    func test_screenshot_unclaimedWindow_errors() throws {
        let (tools, _, _, _) = makeTools()
        XCTAssertThrowsError(try tools.callTool(name: "computer_screenshot", arguments: .object(["window_id": .number(10)]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "window_not_claimed: 10")
        }
    }

    func test_launch_autoClaimsToCaller() throws {
        let (tools, engine, registry, session) = makeTools()
        engine.launchedWindow = WindowInfo(id: 99, appName: "TextEdit", title: "Untitled", bounds: .init(x: 0, y: 0, width: 400, height: 300), pid: 300)
        let result = try tools.callTool(name: "computer_launch", arguments: .object(["app": .string("TextEdit")]))
        guard case .text(let text) = result else { return XCTFail("expected text") }
        XCTAssertTrue(text.contains("99"))
        XCTAssertEqual(registry.owner(of: 99), session)
    }

    func test_act_parsesClickToWindowRelativePoint() throws {
        let (tools, engine, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        _ = try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10),
            "action": .string("click"),
            "x": .number(50), "y": .number(60),
        ]))
        XCTAssertEqual(engine.actions, [.click(point: CGPoint(x: 50, y: 60), button: .left)])
    }

    func test_act_rejectsUnknownAction() throws {
        let (tools, _, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("teleport"),
        ]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "invalid_action: teleport")
        }
    }

    func test_status_setsSessionStatus() throws {
        let (tools, _, registry, session) = makeTools()
        _ = try tools.callTool(name: "computer_status", arguments: .object(["status": .string("Running tests…")]))
        XCTAssertEqual(registry.session(session)?.status, "Running tests…")
    }

    func test_stoppedSession_cannotAct() throws {
        let (tools, _, registry, session) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        registry.stop(session)
        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("click"), "x": .number(1), "y": .number(1),
        ]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "session_stopped")
        }
    }
}
