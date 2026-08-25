import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func extensionRouterParsesBlockingRequestShapes() throws {
    var router = ExtensionUIRouter()

    router.consume(try request("""
        {"type":"extension_ui_request","id":"confirm-1","method":"confirm","title":"Allow command?","message":"Runs pwd","timeout":30000}
        """))
    router.consume(try request("""
        {"type":"extension_ui_request","id":"select-1","method":"select","title":"Choose model","options":["Fast","Smart"],"optionDetails":[{"description":"Lower latency"},{"description":"More capable"}]}
        """))
    router.consume(try request("""
        {"type":"extension_ui_request","id":"input-1","method":"input","title":"Branch name","placeholder":"codex/gui"}
        """))

    #expect(router.inlineRequests.map(\.id) == ["confirm-1", "select-1"])
    #expect(router.sheetRequest?.id == "input-1")
}

@Test func extensionCancelRemovesTheTargetRequest() throws {
    var router = ExtensionUIRouter()
    router.consume(try request("""
        {"type":"extension_ui_request","id":"confirm-1","method":"confirm","title":"Allow?","message":"Run it"}
        """))
    router.consume(try request("""
        {"type":"extension_ui_request","id":"cancel-1","method":"cancel","targetId":"confirm-1"}
        """))

    #expect(router.inlineRequests.isEmpty)
}

@Test func extensionResponsesUseTheExactWireBodies() {
    #expect(ExtensionUIResponse.confirmed(true).body == ["confirmed": .bool(true)])
    #expect(ExtensionUIResponse.value("Fast").body == ["value": .string("Fast")])
    #expect(ExtensionUIResponse.cancelled(timedOut: false).body == ["cancelled": .bool(true)])
    #expect(ExtensionUIResponse.cancelled(timedOut: true).body == [
        "cancelled": .bool(true),
        "timedOut": .bool(true),
    ])
}

private func request(_ json: String) throws -> ExtensionUIRequest {
    guard case .extensionUIRequest(let request) = try RpcFrame.decode(line: Data(json.utf8)) else {
        throw TestRequestError.notAnExtensionRequest
    }
    return request
}

private enum TestRequestError: Error {
    case notAnExtensionRequest
}
