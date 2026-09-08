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

    #expect(router.inlineRequests.map(\.id) == ["confirm-1", "select-1", "input-1"])
    #expect(router.sheetRequest?.id == "input-1")
}

@Test func concurrentInputAndEditorRequestsRemainIndependentlyAddressable() throws {
    var router = ExtensionUIRouter()

    router.consume(try request("""
        {"type":"extension_ui_request","id":"input-1","method":"input","title":"Branch name"}
        """))
    router.consume(try request("""
        {"type":"extension_ui_request","id":"editor-1","method":"editor","title":"Explain the choice","prefill":""}
        """))

    #expect(router.inlineRequests.map(\.id) == ["input-1", "editor-1"])
    #expect(router.containsRequest(id: "input-1"))
    #expect(router.containsRequest(id: "editor-1"))

    router.removeRequest(id: "editor-1")

    #expect(router.containsRequest(id: "input-1"))
    #expect(!router.containsRequest(id: "editor-1"))
}

@Test func providerAccountChannelMarkerIsExcludedButOrdinaryInputRequestsStillReachTheSheet() throws {
    var router = ExtensionUIRouter()

    router.consume(try request("""
        {"type":"extension_ui_request","id":"chan-1","method":"input","title":"\(ExtensionUIRouter.providerAccountChannelTitle)"}
        """))
    #expect(router.sheetRequest == nil)
    #expect(router.inlineRequests.isEmpty)

    // The real login flow answers this same path with an ordinary input
    // dialog (e.g. an API key prompt) — the marker exclusion above must not
    // also swallow this.
    router.consume(try request("""
        {"type":"extension_ui_request","id":"input-1","method":"input","title":"Branch name","placeholder":"codex/gui"}
        """))
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

@Test func onlyExplicitBlockingExtensionRequestsRequireUserInput() {
    let blocking: [ExtensionUIState] = [
        .confirm(id: "confirm", title: "Allow?", message: "Run it", timeout: nil),
        .select(id: "select", title: "Choose", options: [], timeout: nil),
        .input(id: "input", title: "Value", placeholder: nil, timeout: nil),
        .editor(id: "editor", title: "Response", prefill: nil, promptStyle: true),
        .openURL(id: "open", target: URL(string: "https://example.com")!, instructions: nil),
    ]
    let nonblocking: [ExtensionUIState] = [
        .cancel(id: "cancel", targetID: "confirm"),
        .notification(id: "notify", message: "Waiting for input", level: "info"),
        .status(id: "status", key: "copy", text: "Waiting for input"),
        .widget(id: "widget", key: "tasks", lines: ["Waiting for input"], placement: nil),
        .title(id: "title", title: "Waiting for input"),
        .setEditorText(id: "text", text: "Waiting for input"),
    ]

    let allBlockingRequestsRequireInput = blocking.allSatisfy { $0.requiresUserInput }
    #expect(allBlockingRequestsRequireInput)
    #expect(nonblocking.allSatisfy { !$0.requiresUserInput })
    #expect(blocking.filter(\.isQuestionInput).map(\.id) == ["select", "input", "editor"])
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
