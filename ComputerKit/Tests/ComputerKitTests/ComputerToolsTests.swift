import XCTest
@testable import ComputerKit

final class ComputerToolsTests: XCTestCase {
    let safari = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 100, y: 100, width: 800, height: 600), pid: 100)
    let textEdit = WindowInfo(id: 20, appName: "TextEdit", title: "Untitled", bounds: .init(x: 0, y: 0, width: 400, height: 300), pid: 200)

    func makeTools() -> (ComputerTools, FakeEngine, SessionRegistry, SessionID) {
        let engine = FakeEngine()
        engine.windows = [safari, textEdit]
        engine.screenshotPNG = Data([0x89, 0x50])
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        return (ComputerTools(engine: engine, registry: registry, session: session), engine, registry, session)
    }

    func test_windows_listsUnclaimedWithClaimedBy() throws {
        let (tools, _, _, session) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        let result = try tools.callTool(name: "computer_windows", arguments: .object([:]))
        guard case .text(let text) = result else { return XCTFail("expected text") }
        let windows = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        guard case .array(let items) = windows else { return XCTFail("expected array") }
        let claimed = items.first { $0["id"]?.intValue == 10 }
        let unclaimed = items.first { $0["id"]?.intValue == 20 }
        XCTAssertTrue(claimed?["claimed_by"]?.stringValue?.contains("omp") == true)
        XCTAssertTrue(claimed?["claimed_by"]?.stringValue?.contains("\(session)") == true)
        XCTAssertNil(unclaimed?["claimed_by"])
    }

    func test_windowID_rejectsOutOfRange() throws {
        let (tools, _, _, _) = makeTools()
        for windowID in [JSONValue.number(-1), .number(10.5), .number(4_294_967_296)] {
            XCTAssertThrowsError(try tools.callTool(name: "computer_claim", arguments: .object(["window_id": windowID]))) { error in
                XCTAssertEqual(error as? MCPError, MCPError.invalidParams("requires window_id"))
            }
        }
    }

    func test_release_clearsClaim() throws {
        let (tools, _, registry, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        _ = try tools.callTool(name: "computer_release", arguments: .object(["window_id": .number(10)]))
        XCTAssertNil(registry.owner(of: 10))
    }

    func test_release_unclaimedWindow_errors() throws {
        let (tools, _, _, _) = makeTools()
        XCTAssertThrowsError(try tools.callTool(name: "computer_release", arguments: .object(["window_id": .number(10)]))) { error in
            XCTAssertEqual((error as? ComputerError)?.message, "window_not_claimed: 10")
        }
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

    func test_act_clampsOutOfBoundsPoints() throws {
        let (tools, engine, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        _ = try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10),
            "action": .string("click"),
            "x": .number(900), "y": .number(-5),
        ]))
        XCTAssertEqual(engine.actions, [.click(point: CGPoint(x: 799, y: 0), button: .left)])
    }

    func test_offScreenWindow_claimableViaFullList() throws {
        let engine = FakeEngine()
        engine.windows = [safari]
        engine.offScreenWindowIDs = [10]
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let tools = ComputerTools(engine: engine, registry: registry, session: session)
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        XCTAssertEqual(registry.owner(of: 10), session)
    }

    func test_act_rejectsUnknownButton() throws {
        let (tools, _, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10),
            "action": .string("click"),
            "x": .number(1), "y": .number(1),
            "button": .string("middle"),
        ]))) { error in
            XCTAssertEqual(error as? MCPError, MCPError.invalidParams("button must be left or right"))
        }
    }

    func test_act_scrollRequiresNumericDelta() throws {
        let (tools, engine, _, _) = makeTools()
        _ = try tools.callTool(name: "computer_claim", arguments: .object(["window_id": .number(10)]))
        _ = try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10),
            "action": .string("scroll"),
            "delta_y": .number(-3),
        ]))
        XCTAssertEqual(engine.actions, [.scroll(deltaX: 0, deltaY: -3)])

        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("scroll"),
        ]))) { error in
            XCTAssertEqual(error as? MCPError, MCPError.invalidParams("scroll requires delta_x and/or delta_y"))
        }

        XCTAssertThrowsError(try tools.callTool(name: "computer_act", arguments: .object([
            "window_id": .number(10), "action": .string("scroll"), "delta_x": .string("nope"),
        ]))) { error in
            XCTAssertEqual(error as? MCPError, MCPError.invalidParams("scroll requires numeric delta_x"))
        }
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
