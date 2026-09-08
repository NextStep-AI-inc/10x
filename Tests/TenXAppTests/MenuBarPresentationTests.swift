import XCTest
@testable import TenXApp

final class MenuBarPresentationTests: XCTestCase {
    func session(_ id: Int, _ harness: String, windows: [ClaimedWindowState] = []) -> ComputerSessionState {
        ComputerSessionState(id: id, harness: harness, status: nil, windows: windows)
    }

    func window(_ id: Int, _ app: String) -> ClaimedWindowState {
        ClaimedWindowState(windowID: id, app: app, title: "", bounds: "0,0 800x600")
    }

    func test_groupsByHarness_sortedByName() {
        let groups = MenuBarPresentation.groups(sessions: [
            1: session(1, "omp", windows: [window(10, "Safari")]),
            2: session(2, "Cursor", windows: [window(20, "Terminal")]),
            3: session(3, "omp", windows: [window(30, "Notes")]),
        ])
        XCTAssertEqual(groups.map(\.harness), ["Cursor", "omp"])
        XCTAssertEqual(groups[1].sessions.map(\.id), [1, 3])
    }

    func test_sessionsWithoutWindows_areExcluded() {
        let groups = MenuBarPresentation.groups(sessions: [
            1: session(1, "omp", windows: [window(10, "Safari")]),
            2: session(2, "Cursor"), // connected but idle
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].harness, "omp")
    }

    func test_tenXSessions_sortFirst() {
        let groups = MenuBarPresentation.groups(sessions: [
            1: session(1, "Cursor", windows: [window(10, "Safari")]),
            2: session(2, "10x", windows: [window(11, "Terminal")]),
        ])
        XCTAssertEqual(groups.map(\.harness), ["10x", "Cursor"])
    }
}
