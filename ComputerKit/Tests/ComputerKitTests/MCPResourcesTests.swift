import XCTest
@testable import ComputerKit

final class MCPResourcesTests: XCTestCase {
    func test_listsResourcesForClaimedWindows() {
        let engine = FakeEngine()
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let list = resources.listResources()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?["uri"], .string("computer://window/10/screenshot"))
        XCTAssertEqual(list.first?["name"], .string("Safari — Apple"))
        XCTAssertEqual(list.first?["mimeType"], .string("image/png"))
    }

    func test_listResources_includesAllClaimedWindowsAcrossSessions() {
        let engine = FakeEngine()
        let registry = SessionRegistry()
        let sessionA = registry.registerSession(clientName: "omp")
        let sessionB = registry.registerSession(clientName: "Cursor")
        let windowA = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        let windowB = WindowInfo(id: 11, appName: "Terminal", title: "zsh", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 200)
        try! registry.claim(windowA, for: sessionA)
        try! registry.claim(windowB, for: sessionB)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let uris = Set(resources.listResources().compactMap { $0["uri"]?.stringValue })
        XCTAssertEqual(uris, ["computer://window/10/screenshot", "computer://window/11/screenshot"])
    }

    func test_release_removesResourceFromList() {
        let engine = FakeEngine()
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let uri = "computer://window/10/screenshot"
        XCTAssertTrue(resources.listResources().contains { $0["uri"] == .string(uri) })
        XCTAssertTrue(registry.release(window.id))
        XCTAssertFalse(resources.listResources().contains { $0["uri"] == .string(uri) })
        XCTAssertNil(resources.readResource(uri: uri))
    }

    func test_readResource_returnsLatestCapture() {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1, 2, 3])
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let resource = resources.readResource(uri: "computer://window/10/screenshot")
        XCTAssertEqual(resource?["mimeType"], .string("image/png"))
        XCTAssertEqual(resource?["blob"], .string(Data([1, 2, 3]).base64EncodedString()))
    }

    func test_readResource_returnsFreshCaptureEachRead() {
        let engine = FakeEngine()
        engine.screenshotPNG = Data([1, 2, 3])
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        let uri = "computer://window/10/screenshot"
        let first = resources.readResource(uri: uri)?["blob"]?.stringValue
        engine.screenshotPNG = Data([4, 5, 6])
        let second = resources.readResource(uri: uri)?["blob"]?.stringValue
        XCTAssertNotEqual(first, second)
    }

    func test_readResource_unknownURI_returnsNil() {
        let resources = ScreenshotResources(engine: FakeEngine(), registry: SessionRegistry())
        XCTAssertNil(resources.readResource(uri: "computer://window/999/screenshot"))
    }

    func test_readResource_oversizedWindowID_returnsNil() {
        let resources = ScreenshotResources(engine: FakeEngine(), registry: SessionRegistry())
        XCTAssertNil(resources.readResource(uri: "computer://window/99999999999/screenshot"))
    }

    func test_readResource_negativeWindowID_returnsNil() {
        let resources = ScreenshotResources(engine: FakeEngine(), registry: SessionRegistry())
        XCTAssertNil(resources.readResource(uri: "computer://window/-1/screenshot"))
    }

    func test_readResource_malformedURIs_returnNil() {
        let engine = FakeEngine()
        let registry = SessionRegistry()
        let session = registry.registerSession(clientName: "omp")
        let window = WindowInfo(id: 10, appName: "Safari", title: "Apple", bounds: .init(x: 0, y: 0, width: 800, height: 600), pid: 100)
        try! registry.claim(window, for: session)
        let resources = ScreenshotResources(engine: engine, registry: registry)
        for uri in [
            "computer://window//screenshot",
            "computer://window/10/extra/screenshot",
            "computer://window/%31%30/screenshot",
        ] {
            XCTAssertNil(resources.readResource(uri: uri), uri)
        }
    }
}
