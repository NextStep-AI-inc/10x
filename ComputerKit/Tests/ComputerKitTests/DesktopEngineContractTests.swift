import XCTest
@testable import ComputerKit

/// Pins the DesktopEngine contract against the fake so registry/tool tasks
/// never touch the real OS.
final class DesktopEngineContractTests: XCTestCase {
    func test_fake_listsWindowsAndClaimsNothingByDefault() {
        let engine = FakeEngine()
        engine.windows = [
            WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100),
        ]
        XCTAssertEqual(try engine.listWindows().map(\.appName), ["Safari"])
    }

    func test_fake_recordsActions() throws {
        let engine = FakeEngine()
        engine.windows = [WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)]
        try engine.act(.click(point: .init(x: 10, y: 10), button: .left), window: engine.windows[0])
        XCTAssertEqual(engine.actions.count, 1)
    }

    func test_fake_screenshotReturnsStoredPNG() throws {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([0x89, 0x50, 0x4E, 0x47])
        let shot = try engine.screenshot(windowID: 10)
        XCTAssertEqual(shot.pngData, Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
