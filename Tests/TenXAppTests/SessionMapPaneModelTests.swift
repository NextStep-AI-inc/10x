import Testing
@testable import TenXApp

@MainActor
@Test func sessionMapFailedUpdateKeepsLastDocument() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.planningXML)
    let model = SessionMapPaneModel(displayedDocument: document, state: .ready)

    model.transition(to: .writing)
    model.transition(to: .failed(message: "provider/model/raw-id"))

    #expect(model.displayedDocument == document)
    #expect(model.state == .failed(message: "provider/model/raw-id"))
}

@MainActor
@Test func sessionMapReplacementReconcilesFocusWhilePaneIsClosed() throws {
    let previous = try SessionMapFixtures.document(SessionMapFixtures.identityPreviousXML)
    let replacement = try SessionMapFixtures.document(SessionMapFixtures.focusReorderedXML)
    let model = SessionMapPaneModel(
        displayedDocument: previous,
        state: .ready,
        focus: SessionMapFocus(
            selectedNodeID: "view",
            hoveredNodeID: "service",
            focusedNodeID: "view",
            flowStepIndex: 0),
        isVisible: false)

    model.replaceDocument(replacement)

    #expect(model.displayedDocument == replacement)
    #expect(model.focus.selectedNodeID == "view")
    #expect(model.focus.hoveredNodeID == "service")
    #expect(model.focus.focusedNodeID == "view")
    #expect(model.focus.flowStepIndex == 1)
}
