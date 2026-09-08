import Foundation
import Testing
@testable import TenXApp

@Test func sessionMapEdgeLabelDisplayFitsItsPlannedFrame() {
    let label = "continues to the next processing stage"
    let displayed = SessionMapGraphView.displayedEdgeLabel(label, width: 112)

    #expect(displayed == "continues to …")
    #expect(displayed.count * 7 + 12 <= 112)
    #expect(SessionMapGraphView.displayedEdgeLabel("XML", width: 36) == "XML")
}

@Test func sessionMapLayoutSeparatesNodesAndRetainsSiblingOrder() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.denseXML)
    let layout = SessionMapLayout.layout(
        graph: document.graph, firstSeenOrder: [], measuredHeights: [:]
    )
    let repeated = SessionMapLayout.layout(
        graph: document.graph, firstSeenOrder: [], measuredHeights: [:]
    )

    #expect(layout == repeated)
    #expect(layout.frames.count == document.graph.nodes.count)
    #expect(layout.edges.count == document.graph.edges.count)
    expectValidGeometry(layout, graph: document.graph)

    let initial = SessionMapGraph(
        nodes: [node("alpha"), node("beta")], edges: []
    )
    let initialLayout = SessionMapLayout.layout(
        graph: initial, firstSeenOrder: [], measuredHeights: [:]
    )
    let updated = SessionMapGraph(
        nodes: [node("beta"), node("gamma"), node("alpha")], edges: []
    )
    let updatedLayout = SessionMapLayout.layout(
        graph: updated,
        firstSeenOrder: initialLayout.firstSeenOrder,
        measuredHeights: [:]
    )

    #expect(updatedLayout.firstSeenOrder == ["alpha", "beta", "gamma"])
    #expect(updatedLayout.frames["alpha"] == CGRect(x: 16, y: 16, width: 124, height: 64))
    #expect(updatedLayout.frames["beta"] == CGRect(x: 156, y: 16, width: 124, height: 64))
    #expect(updatedLayout.frames["gamma"] == CGRect(x: 296, y: 16, width: 124, height: 64))
    #expect(try #require(updatedLayout.frames["alpha"]).minX
        < #require(updatedLayout.frames["beta"]).minX)
    #expect(try #require(updatedLayout.frames["beta"]).minX
        < #require(updatedLayout.frames["gamma"]).minX)
}

@Test func sessionMapLayoutHandlesCyclesAndWrappedRanks() throws {
    let document = try SessionMapFixtures.document(SessionMapFixtures.layoutStressXML)
    let measuredHeights: [String: CGFloat] = [
        "root-2": 96,
        "root-5": 112,
        "disconnected": 112,
    ]
    let layout = SessionMapLayout.layout(
        graph: document.graph,
        firstSeenOrder: document.graph.nodes.map(\.id),
        measuredHeights: measuredHeights
    )

    #expect(layout == SessionMapLayout.layout(
        graph: document.graph,
        firstSeenOrder: document.graph.nodes.map(\.id),
        measuredHeights: measuredHeights
    ))
    #expect(layout.frames.count == document.graph.nodes.count)
    #expect(layout.size.width.isFinite && layout.size.width > 0)
    #expect(layout.size.height.isFinite && layout.size.height > 0)
    expectValidGeometry(layout, graph: document.graph)

    let wrappedBottom = try (1...7).map { index in
        try #require(layout.frames["root-\(index)"]).maxY
    }.max() ?? 0
    #expect(try #require(layout.frames["dependent"]).minY > wrappedBottom)
    #expect(layout.edges.contains { route in
        route.edge.from == "cycle-a" && route.edge.to == "cycle-a" && route.isBackEdge
    })
    #expect(layout.edges.contains { route in
        route.edge.from != route.edge.to && route.isBackEdge
    })

    let wrappedRoute = try #require(layout.edges.first { route in
        route.edge.from == "root-1" && route.edge.to == "root-7"
    })
    #expect(!wrappedRoute.sideLanePoints.isEmpty)
    let wrappedPoints = [wrappedRoute.start] + wrappedRoute.sideLanePoints + [wrappedRoute.end]
    for pair in zip(wrappedPoints, wrappedPoints.dropFirst()) {
        for (id, frame) in layout.frames where id != "root-1" && id != "root-7" {
            #expect(!segmentIntersectsInterior(pair.0, pair.1, frame))
        }
    }

    for route in layout.edges where !route.sideLanePoints.isEmpty {
        let points = [route.start] + route.sideLanePoints + [route.end]
        for pair in zip(points, points.dropFirst()) {
            for (id, frame) in layout.frames
                where id != route.edge.from && id != route.edge.to
            {
                #expect(!segmentIntersectsInterior(pair.0, pair.1, frame))
            }
        }
    }

    let panning = SessionMapLayout.viewportGeometry(
        canvasSize: CGSize(width: 1_000, height: 800),
        viewportSize: CGSize(width: 600, height: 500)
    )
    #expect(panning.scale == 0.8)
    #expect(panning.panBounds == CGSize(width: 200, height: 140))

    let fitted = SessionMapLayout.viewportGeometry(
        canvasSize: CGSize(width: 400, height: 300),
        viewportSize: CGSize(width: 600, height: 500)
    )
    #expect(fitted.scale == 1)
    #expect(fitted.panBounds == .zero)
}

private func expectValidGeometry(
    _ layout: SessionMapLayoutResult,
    graph: SessionMapGraph
) {
    let frames = graph.nodes.compactMap { layout.frames[$0.id] }
    #expect(frames.count == graph.nodes.count)

    for i in frames.indices {
        for j in frames.indices where i < j {
            #expect(!frames[i].intersects(frames[j]))
        }
    }
    for frame in frames {
        #expect(frame.minX.isFinite && frame.minY.isFinite)
        #expect(frame.width.isFinite && frame.height.isFinite)
        #expect(frame.minX >= 0 && frame.maxX <= layout.size.width)
        #expect(frame.minY >= 0 && frame.maxY <= layout.size.height)
    }
    for route in layout.edges {
        let points = [route.start, route.end]
            + [route.controlPoint1, route.controlPoint2].compactMap { $0 }
            + route.sideLanePoints
        #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        if let labelFrame = route.labelFrame {
            #expect(!frames.contains { $0.intersects(labelFrame) })
        }
        #expect(route.accessibleLabel == route.edge.label)
    }
}

private func node(_ id: String) -> SessionMapNode {
    SessionMapNode(
        id: id, label: id.capitalized, kind: .component,
        file: nil, status: .planned, group: nil, ref: nil, note: nil
    )
}

private func segmentIntersectsInterior(
    _ start: CGPoint,
    _ end: CGPoint,
    _ frame: CGRect
) -> Bool {
    let interior = frame.insetBy(dx: 0.5, dy: 0.5)
    if start.x == end.x {
        return start.x > interior.minX && start.x < interior.maxX
            && max(start.y, end.y) > interior.minY
            && min(start.y, end.y) < interior.maxY
    }
    if start.y == end.y {
        return start.y > interior.minY && start.y < interior.maxY
            && max(start.x, end.x) > interior.minX
            && min(start.x, end.x) < interior.maxX
    }
    return false
}
