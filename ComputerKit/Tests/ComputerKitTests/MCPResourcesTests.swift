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
        XCTAssertEqual(list.first?["uri"], .string("computer://window/10/screenshot"))
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

    func test_readResource_unknownURI_returnsNil() {
        let resources = ScreenshotResources(engine: FakeEngine(), registry: SessionRegistry())
        XCTAssertNil(resources.readResource(uri: "computer://window/999/screenshot"))
    }
}
