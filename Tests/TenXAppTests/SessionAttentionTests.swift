import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func focusPendingRequestChoosesTheEarliestRequestInTranscriptOrder() {
    let controller = attentionController(items: [
        .notice(id: "before", level: "info", message: "Before"),
        .extensionUI(.select(
            id: "select",
            title: "Choose",
            options: [],
            timeout: nil)),
        .extensionUI(.confirm(
            id: "confirm",
            title: "Allow?",
            message: "Run it",
            timeout: nil)),
    ])
    controller.draft = "Keep this draft"
    let attachment = ComposerAttachment(
        name: "evidence.png",
        data: Data([1]),
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1)
    controller.attachments = [attachment]
    let originalItems = controller.items

    controller.focusPendingRequest()

    #expect(controller.transcriptNavigationRequest?.rowID == "extension-ui:select")
    #expect(controller.items == originalItems)
    #expect(controller.draft == "Keep this draft")
    #expect(controller.attachments == [attachment])
}

@MainActor
@Test func previewControllerDerivesPendingActivityFromItsTranscript() {
    let controller = attentionController(items: [
        .extensionUI(.confirm(
            id: "confirm",
            title: "Allow?",
            message: "Run it",
            timeout: nil)),
    ])

    #expect(controller.activityState == .needsInput)
}

@MainActor
@Test func focusPendingRequestRecognizesEveryInteractiveRequestShape() {
    let requests: [ExtensionUIState] = [
        .confirm(id: "confirm", title: "Allow?", message: "Run it", timeout: nil),
        .select(id: "select", title: "Choose", options: [], timeout: nil),
        .input(id: "input", title: "Value", placeholder: nil, timeout: nil),
        .editor(id: "editor", title: "Response", prefill: nil, promptStyle: true),
        .openURL(
            id: "open",
            target: URL(string: "https://example.com")!,
            instructions: nil),
    ]

    for request in requests {
        let controller = attentionController(items: [
            .extensionUI(request),
            .extensionUI(.confirm(
                id: "later",
                title: "Later",
                message: "Later request",
                timeout: nil)),
        ])

        controller.focusPendingRequest()

        #expect(controller.transcriptNavigationRequest?.rowID == "extension-ui:\(request.id)")
    }
}

@MainActor
@Test func focusPendingRequestIsANoopWithoutAPendingRequest() throws {
    let controller = attentionController(items: [
        .notice(id: "notice", level: "info", message: "No response needed"),
    ])
    let search = try #require(TranscriptSearchRequest(entryID: "notice", query: "response"))
    controller.focusSearchResult(search)

    controller.focusPendingRequest()

    #expect(controller.transcriptNavigationRequest == nil)
    #expect(controller.transcriptSearchRequest == search)
    #expect(!controller.viewport.isFollowingLatest)
}

@MainActor
@Test func repeatedPendingRequestActivationCreatesAFreshNavigationIdentity() throws {
    let controller = attentionController(items: [
        .extensionUI(.input(
            id: "input",
            title: "Value",
            placeholder: nil,
            timeout: nil)),
    ])

    controller.focusPendingRequest()
    let first = try #require(controller.transcriptNavigationRequest)
    controller.focusPendingRequest()
    let second = try #require(controller.transcriptNavigationRequest)

    #expect(first.rowID == second.rowID)
    #expect(first.nonce != second.nonce)
}

@MainActor
@Test func explicitRowNavigationClearsSearchAndStopsFollowingLatest() throws {
    let controller = attentionController(items: [])
    let search = try #require(TranscriptSearchRequest(entryID: "message", query: "needle"))
    controller.focusSearchResult(search)
    controller.viewport.isFollowingLatest = true

    controller.focusTranscriptRow(TranscriptNavigationRequest(rowID: "message:target"))

    #expect(controller.transcriptSearchRequest == nil)
    #expect(!controller.viewport.isFollowingLatest)
    #expect(controller.transcriptNavigationRequest?.rowID == "message:target")

    controller.focusTranscriptRow(nil)

    #expect(controller.transcriptNavigationRequest == nil)
}

@MainActor
@Test func pendingRequestArrivalDoesNotPublishNavigationOrChangeReaderState() {
    let controller = attentionController(items: [
        .extensionUI(.confirm(
            id: "confirm",
            title: "Allow?",
            message: "Run it",
            timeout: nil)),
    ])
    controller.viewport.isFollowingLatest = false

    #expect(controller.transcriptNavigationRequest == nil)
    #expect(!controller.viewport.isFollowingLatest)
}

@MainActor
private func attentionController(items: [TranscriptItem]) -> SessionController {
    SessionController(
        processManager: SessionProcessManager(),
        previewItems: items,
        runtimeState: .idle)
}
