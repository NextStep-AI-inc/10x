import Testing
@testable import TenXApp

@Test func sessionMapFocusHighlightsOnlyDirectConnections() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.chainXML)
    let focus = SessionMapFocus(
        selectedNodeID: nil,
        hoveredNodeID: "view",
        focusedNodeID: nil,
        flowStepIndex: nil)

    #expect(SessionMapInteraction.highlightedNodeIDs(graph: document.graph, focus: focus) == ["view", "service"])
}

@Test func sessionMapWalkthroughKeepsFocusAfterStatusUpdate() throws {
    let previous = try SessionMapFixtures.document(SessionMapFixtures.planningXML)
    let updated = try SessionMapFixtures.document(
        SessionMapFixtures.planningXML.replacingOccurrences(
            of: "status=\"planned\" ref=\"u1\">Carries graph",
            with: "status=\"active\" ref=\"u1\">Carries graph"))
    let focus = SessionMapFocus(
        selectedNodeID: "document",
        hoveredNodeID: nil,
        focusedNodeID: nil,
        flowStepIndex: 2)

    #expect(SessionMapInteraction.reconciledFocus(
        focus, replacing: previous, with: updated
    ) == focus)
}

@Test func sessionMapRemovedFlowStepResetsSelection() throws {
    let previous = try SessionMapFixtures.document(SessionMapFixtures.chainXML)
    let updated = try SessionMapFixtures.document("""
        <sessionmap headline="Request path" phase="planning">
          <summary>The request begins in the view.</summary>
          <map><node id="view" label="Request view" kind="view" status="planned" ref="u1"/></map>
          <flow title="Request"><step node="view">Enter the request.</step></flow>
        </sessionmap>
        """)
    let focus = SessionMapFocus(
        selectedNodeID: "service",
        hoveredNodeID: "service",
        focusedNodeID: "service",
        flowStepIndex: 1)

    #expect(SessionMapInteraction.reconciledFocus(
        focus, replacing: previous, with: updated
    ) == SessionMapFocus(
        selectedNodeID: nil,
        hoveredNodeID: nil,
        focusedNodeID: nil,
        flowStepIndex: nil))
}

@Test func sessionMapAccessibilityNamesRelationshipsWithoutNodeIDs() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.chainXML)

    #expect(SessionMapInteraction.accessibilityLabel(
        for: document.graph.nodes[0], graph: document.graph
    ) == "Request view, Planned. Connects to Service.")
}
