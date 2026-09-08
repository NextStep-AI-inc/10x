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

@MainActor
@Test func sessionMapSaveFailureRemainsPresentableUntilNextAttempt() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.planningXML)
    let model = SessionMapPaneModel(displayedDocument: document, state: .ready)

    model.retainFailure(message: "The updated map could not be saved.")

    #expect(model.displayedDocument == document)
    #expect(model.state == .stale)
    #expect(model.retainedFailureMessage == "The updated map could not be saved.")
    model.transition(to: .writing)
    #expect(model.retainedFailureMessage == nil)
}
