import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func sessionMapGraphSnapshots() throws {
    let states: [(String, SessionMapFocus, Bool)] = [
        ("normal", SessionMapFocus(
            selectedNodeID: nil, hoveredNodeID: nil, focusedNodeID: nil, flowStepIndex: nil), false),
        ("hover", SessionMapFocus(
            selectedNodeID: nil, hoveredNodeID: "writer", focusedNodeID: nil, flowStepIndex: nil), false),
        ("focused", SessionMapFocus(
            selectedNodeID: nil, hoveredNodeID: nil, focusedNodeID: "document", flowStepIndex: nil), false),
        ("walkthrough", SessionMapFocus(
            selectedNodeID: "handler", hoveredNodeID: nil, focusedNodeID: nil, flowStepIndex: 3), true),
    ]
    for appearance in [SnapshotAppearance.light, .dark] {
        let suffix: String
        switch appearance {
        case .light: suffix = ""
        case .dark: suffix = "-dark"
        }
        for state in states {
            try assertSnapshot(
                SessionMapGraphSnapshotHarness(
                    initialFocus: state.1,
                    showsWalkthrough: state.2),
                name: "session-map-graph-\(state.0)\(suffix)",
                appearance: appearance,
                size: CGSize(width: 440, height: 820))
        }
    }
}

private struct SessionMapGraphSnapshotHarness: View {
    @State private var focus: SessionMapFocus
    let showsWalkthrough: Bool

    init(initialFocus: SessionMapFocus, showsWalkthrough: Bool) {
        _focus = State(initialValue: initialFocus)
        self.showsWalkthrough = showsWalkthrough
    }

    var body: some View {
        let document = try? SessionMapFixtures.document(SessionMapFixtures.graphStatesXML)
        if let document {
            let layout = SessionMapLayout.layout(
                graph: document.graph,
                firstSeenOrder: [],
                measuredHeights: SessionMapGraphView.measuredHeights(for: document.graph))
            VStack(alignment: .leading, spacing: 12) {
                Text("Architecture")
                    .font(TenXTypography.accent(size: 16))
                    .fixedSize()
                SessionMapGraphView(
                    document: document,
                    layout: layout,
                    focus: $focus,
                    activity: SessionMapActivity(
                        activeNodeIDs: ["writer"],
                        unmappedDescriptions: ["Reading a supporting file"]),
                    changes: SessionMapChanges(
                        addedNodeIDs: ["audit"],
                        changedNodeIDs: ["handler"],
                        removedNodeIDs: [],
                        addedEdgeKeys: [],
                        changedEdgeKeys: [],
                        removedEdgeKeys: []),
                    onAction: { _ in })
                if showsWalkthrough, let flow = document.flow {
                    SessionMapWalkthroughView(flow: flow, focus: $focus, onAction: { _ in })
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
