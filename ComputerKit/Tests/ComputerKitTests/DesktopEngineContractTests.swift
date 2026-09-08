import XCTest
@testable import ComputerKit

/// Pins the DesktopEngine contract against the fake so registry/tool tasks
/// never touch the real OS.
final class DesktopEngineContractTests: XCTestCase {
    func test_fake_listsSeededWindows() throws {
        let engine = FakeEngine()
        engine.windows = [
            WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100),
        ]
        XCTAssertEqual(try engine.listWindows(onScreenOnly: true).map(\.appName), ["Safari"])
    }

    func test_fake_recordsActions() throws {
        let engine = FakeEngine()
        engine.windows = [WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)]
        let click = ComputerAction.click(point: .init(x: 10, y: 10), button: .left)
        try engine.act(click, window: engine.windows[0])
        XCTAssertEqual(engine.actions, [click])
    }

    func test_fake_screenshotReturnsStoredPNG() throws {
        let engine = FakeEngine()
        engine.windows = [WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)]
        engine.screenshotPNG = Data([0x89, 0x50, 0x4E, 0x47])
        let shot = try engine.screenshot(windowID: 10)
        XCTAssertEqual(shot.pngData, Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func test_fake_launchReturnsAndAppendsOrThrows() throws {
        let engine = FakeEngine()
        XCTAssertThrowsError(try engine.launch(app: "Notes")) { error in
            XCTAssertEqual(error as? ComputerError, ComputerError("no such app: Notes"))
        }

        let window = WindowInfo(id: 20, appName: "Notes", title: "Notes", bounds: .init(x: 0, y: 0, width: 400, height: 300), pid: 200)
        engine.launchedWindow = window
        let returned = try engine.launch(app: "Notes")
        XCTAssertEqual(returned, window)
        XCTAssertEqual(engine.windows, [window])
    }

    func test_fake_preflightPermissionsReturnsStoredStatus() {
        let engine = FakeEngine()
        engine.permissionStatus = PermissionStatus(screenRecording: false, accessibility: true)
        XCTAssertEqual(engine.preflightPermissions(), PermissionStatus(screenRecording: false, accessibility: true))
    }
}
