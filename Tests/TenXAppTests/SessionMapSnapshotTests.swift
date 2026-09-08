import AppKit
import SwiftUI
import Testing
@testable import TenXApp

@MainActor
@Test func sessionMapDuplicateChartLabelsRemainDistinct() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.duplicateChartLabelsXML)
    let block = try #require(document.blocks.first)
    let view = SessionMapSupportingBlockView(block: block, onAction: { _ in })
        .padding(16)
        .frame(width: 320, height: 180, alignment: .topLeading)
    let bitmap = try #require(renderSnapshotBitmap(
        view,
        size: CGSize(width: 320, height: 180)))

    #expect(cyanMarkRuns(in: bitmap) == 2)
    try assertSnapshot(
        view,
        name: "session-map-chart-duplicate-labels",
        size: CGSize(width: 320, height: 180))
}

@MainActor
@Test func sessionMapPanePlacesDiagramBeforeSupportingProse() throws {
    #expect(SessionMapFixtures.supportingSummary.count == 600)
    let document = try SessionMapFixtures.document(SessionMapFixtures.supportingXML)
    let model = SessionMapPaneModel(displayedDocument: document, state: .ready, isVisible: true)
    try assertSnapshot(
        sessionMapSnapshotView(model: model),
        name: "session-map-diagram-first",
        size: CGSize(width: 440, height: 760))
}

@MainActor
@Test func sessionMapPaneStateSnapshots() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.supportingXML)
    let states: [(String, SessionMapPaneState, SessionMapDocument?)] = [
        ("supporting", .ready, document),
        ("empty", .empty, nil),
        ("stale", .stale, document),
        ("failed", .failed(message: "provider/model/raw-id"), document),
        ("checking", .checking, document),
        ("needs-model", .needsModel, nil),
    ]
    for appearance in [SnapshotAppearance.light, .dark] {
        for width in [320, 440] {
            for state in states {
                let model = SessionMapPaneModel(
                    displayedDocument: state.2,
                    state: state.1,
                    paneWidth: CGFloat(width),
                    isVisible: true)
                try assertSnapshot(
                    sessionMapSnapshotView(model: model),
                    name: "session-map-\(state.0)-\(width)\(appearance == .dark ? "-dark" : "")",
                    appearance: appearance,
                    size: CGSize(width: width, height: 760))
            }
        }
    }
}

@MainActor
@Test func sessionMapSupportingLeavesSnapshots() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.supportingXML)
    for appearance in [SnapshotAppearance.light, .dark] {
        for width in [320, 440] {
            try assertSnapshot(
                sessionMapSupportingSnapshotView(document: document, width: CGFloat(width)),
                name: "session-map-supporting-leaves-\(width)\(appearance == .dark ? "-dark" : "")",
                appearance: appearance,
                size: CGSize(width: width, height: 900))
        }
    }
}

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

@MainActor
private func sessionMapSnapshotView(model: SessionMapPaneModel) -> some View {
    SessionMapPaneView(
        model: model,
        activity: model.displayedDocument == nil ? .empty : SessionMapActivity(
            activeNodeIDs: ["document"],
            unmappedDescriptions: ["Running focused tests"]),
        updatedAt: Date(timeIntervalSince1970: 1_788_800_000),
        attribution: "Generated from session. Layout not checked.")
        .environment(sessionMapSnapshotIDEStore())
        .environment(\.fileReferenceBaseURL, sessionMapSnapshotProjectURL)
}

@MainActor
private func sessionMapSupportingSnapshotView(
    document: SessionMapDocument,
    width: CGFloat
) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
            SessionMapSupportingBlockView(block: block, onAction: { _ in })
        }
    }
    .padding(16)
    .frame(width: width, alignment: .leading)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .environment(sessionMapSnapshotIDEStore())
    .environment(\.fileReferenceBaseURL, sessionMapSnapshotProjectURL)
}

@MainActor
private func sessionMapSnapshotIDEStore() -> IDEPreferenceStore {
    let defaults = UserDefaults(suiteName: "TenXAppTests.SessionMapSnapshots") ?? .standard
    defaults.removePersistentDomain(forName: "TenXAppTests.SessionMapSnapshots")
    return IDEPreferenceStore(
        defaults: defaults,
        registry: IDERegistry.testing(applications: [
            "com.todesktop.230313mzl4w4u92": URL(filePath: "/Applications/Cursor.app"),
        ]))
}

private let sessionMapSnapshotProjectURL = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func cyanMarkRuns(in bitmap: NSBitmapImageRep) -> Int {
    let occupiedColumns = (0..<bitmap.pixelsWide).map { x in
        (0..<bitmap.pixelsHigh).contains { y in
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                return false
            }
            return color.redComponent < 0.05
                && color.greenComponent > 0.55
                && color.blueComponent > 0.65
                && color.blueComponent < 0.9
        }
    }
    return occupiedColumns.reduce(into: (count: 0, previous: false)) { result, occupied in
        if occupied && !result.previous { result.count += 1 }
        result.previous = occupied
    }.count
}
