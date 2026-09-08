import Foundation

struct SessionMapEdgeRoute: Equatable, Sendable {
    let edge: SessionMapEdge
    let start: CGPoint
    let end: CGPoint
    let controlPoint1: CGPoint?
    let controlPoint2: CGPoint?
    let sideLanePoints: [CGPoint]
    let labelFrame: CGRect?
    let accessibleLabel: String?
    let isBackEdge: Bool
}

struct SessionMapLayoutDiagnostic: Equatable, Sendable {
    let code: String
    let message: String
}

struct SessionMapLayoutResult: Equatable, Sendable {
    let frames: [String: CGRect]
    let edges: [SessionMapEdgeRoute]
    let size: CGSize
    let firstSeenOrder: [String]
    let diagnostics: [SessionMapLayoutDiagnostic]
}

struct SessionMapViewportGeometry: Equatable, Sendable {
    let scale: CGFloat
    let panBounds: CGSize
}

enum SessionMapLayout {
    private static let cardWidth: CGFloat = 124
    private static let cardHeight: CGFloat = 64
    private static let horizontalGap: CGFloat = 16
    private static let rowGap: CGFloat = 32
    private static let padding: CGFloat = 16
    private static let maximumColumns = 3
    private static let sideLaneGap: CGFloat = 24
    private static let maximumDiagnostics = 20

    static func layout(
        graph: SessionMapGraph,
        firstSeenOrder: [String],
        measuredHeights: [String: CGFloat]
    ) -> SessionMapLayoutResult {
        let nodeIDs = Set(graph.nodes.map(\.id))
        var retainedOrder: [String] = []
        var retainedIDs: Set<String> = []
        for id in firstSeenOrder where nodeIDs.contains(id) {
            if retainedIDs.insert(id).inserted {
                retainedOrder.append(id)
            }
        }
        for node in graph.nodes where retainedIDs.insert(node.id).inserted {
            retainedOrder.append(node.id)
        }

        var orderIndices: [String: Int] = [:]
        for (index, id) in retainedOrder.enumerated() {
            orderIndices[id] = index
        }

        let rankEdgeIndices = graph.edges.indices.filter { index in
            let edge = graph.edges[index]
            return (edge.kind == .depends || edge.kind == .flow)
                && nodeIDs.contains(edge.from) && nodeIDs.contains(edge.to)
        }
        let backEdgeIndices = classifyBackEdges(
            graph: graph, rankEdgeIndices: rankEdgeIndices, nodeIDs: nodeIDs
        )
        let ranks = longestPathRanks(
            graph: graph,
            rankEdgeIndices: rankEdgeIndices,
            backEdgeIndices: backEdgeIndices
        )

        var diagnostics: [SessionMapLayoutDiagnostic] = []
        var heights: [String: CGFloat] = [:]
        for node in graph.nodes {
            let measured = measuredHeights[node.id] ?? cardHeight
            if measured.isFinite, measured > 0 {
                heights[node.id] = max(cardHeight, min(measured, 2_048))
            } else {
                heights[node.id] = cardHeight
                appendDiagnostic(
                    code: "invalid-measurement",
                    message: "Used the default height for node \(node.id).",
                    to: &diagnostics
                )
            }
        }

        let nodesByRank = Dictionary(grouping: graph.nodes) { ranks[$0.id, default: 0] }
        var frames: [String: CGRect] = [:]
        var rowTops: [String: CGFloat] = [:]
        var rowBottoms: [String: CGFloat] = [:]
        var currentY = padding
        for rank in nodesByRank.keys.sorted() {
            let nodes = nodesByRank[rank, default: []].sorted { lhs, rhs in
                orderIndices[lhs.id, default: .max] < orderIndices[rhs.id, default: .max]
            }
            for rowStart in stride(from: 0, to: nodes.count, by: maximumColumns) {
                let rowEnd = min(rowStart + maximumColumns, nodes.count)
                let row = nodes[rowStart..<rowEnd]
                let rowHeight = row.map { heights[$0.id, default: cardHeight] }.max() ?? cardHeight
                for (column, node) in row.enumerated() {
                    rowTops[node.id] = currentY
                    rowBottoms[node.id] = currentY + rowHeight
                    frames[node.id] = CGRect(
                        x: padding + CGFloat(column) * (cardWidth + horizontalGap),
                        y: currentY,
                        width: cardWidth,
                        height: heights[node.id, default: cardHeight]
                    )
                }
                currentY += rowHeight + rowGap
            }
        }

        let cardRight = frames.values.map(\.maxX).max() ?? padding
        let canvasHeight = graph.nodes.isEmpty
            ? padding * 2
            : currentY - rowGap + padding
        let routeEdgeIndices = graph.edges.indices.sorted { lhs, rhs in
            edgeComesBefore(graph.edges[lhs], graph.edges[rhs], lhsIndex: lhs, rhsIndex: rhs)
        }
        let sideEdgeIndices = routeEdgeIndices.filter { index in
            guard let source = frames[graph.edges[index].from],
                  let target = frames[graph.edges[index].to]
            else { return false }
            let edge = graph.edges[index]
            return backEdgeIndices.contains(index)
                || ranks[edge.from, default: 0] == ranks[edge.to, default: 0]
                || target.minY <= source.maxY
        }
        var sideLaneIndices: [Int: Int] = [:]
        for (lane, edgeIndex) in sideEdgeIndices.enumerated() {
            sideLaneIndices[edgeIndex] = lane
        }

        var routes: [SessionMapEdgeRoute] = []
        var visibleLabelFrames: [CGRect] = []
        for index in routeEdgeIndices {
            let edge = graph.edges[index]
            guard let source = frames[edge.from], let target = frames[edge.to] else {
                appendDiagnostic(
                    code: "missing-edge-endpoint",
                    message: "Could not route \(edge.from) to \(edge.to).",
                    to: &diagnostics
                )
                continue
            }

            let isBackEdge = backEdgeIndices.contains(index)
            if let lane = sideLaneIndices[index] {
                let laneX = cardRight + sideLaneGap * CGFloat(lane + 1)
                let start = CGPoint(x: source.midX, y: source.maxY)
                let entersFromTop = target.minY > source.maxY
                let end = CGPoint(
                    x: target.midX,
                    y: entersFromTop ? target.minY : target.maxY
                )
                let departureY = rowBottoms[edge.from, default: source.maxY] + rowGap / 2
                let approachY = entersFromTop
                    ? rowTops[edge.to, default: target.minY] - rowGap / 2
                    : rowBottoms[edge.to, default: target.maxY] + rowGap / 2
                let points = [
                    CGPoint(x: start.x, y: departureY),
                    CGPoint(x: laneX, y: departureY),
                    CGPoint(x: laneX, y: approachY),
                    CGPoint(x: end.x, y: approachY),
                ]
                routes.append(SessionMapEdgeRoute(
                    edge: edge,
                    start: start,
                    end: end,
                    controlPoint1: nil,
                    controlPoint2: nil,
                    sideLanePoints: points,
                    labelFrame: nil,
                    accessibleLabel: edge.label,
                    isBackEdge: isBackEdge
                ))
                continue
            }

            let start = CGPoint(x: source.midX, y: source.maxY)
            let end = CGPoint(x: target.midX, y: target.minY)
            let controlY = start.y + (end.y - start.y) / 2
            let labelFrame = freeLabelFrame(
                for: edge.label,
                center: CGPoint(x: (start.x + end.x) / 2, y: controlY),
                nodeFrames: Array(frames.values),
                occupiedLabelFrames: visibleLabelFrames
            )
            if let labelFrame {
                visibleLabelFrames.append(labelFrame)
            } else if edge.label != nil {
                appendDiagnostic(
                    code: "edge-label-hidden",
                    message: "Kept the label for \(edge.from) to \(edge.to) accessible.",
                    to: &diagnostics
                )
            }
            routes.append(SessionMapEdgeRoute(
                edge: edge,
                start: start,
                end: end,
                controlPoint1: CGPoint(x: start.x, y: controlY),
                controlPoint2: CGPoint(x: end.x, y: controlY),
                sideLanePoints: [],
                labelFrame: labelFrame,
                accessibleLabel: edge.label,
                isBackEdge: isBackEdge
            ))
        }

        let canvasWidth = sideEdgeIndices.isEmpty
            ? cardRight + padding
            : cardRight + sideLaneGap * CGFloat(sideEdgeIndices.count) + padding
        appendGeometryDiagnostics(
            graph: graph,
            frames: frames,
            routes: routes,
            size: CGSize(width: canvasWidth, height: canvasHeight),
            to: &diagnostics
        )

        return SessionMapLayoutResult(
            frames: frames,
            edges: routes,
            size: CGSize(width: canvasWidth, height: canvasHeight),
            firstSeenOrder: retainedOrder,
            diagnostics: diagnostics
        )
    }

    static func viewportGeometry(
        canvasSize: CGSize,
        viewportSize: CGSize
    ) -> SessionMapViewportGeometry {
        let canvasWidth = canvasSize.width.isFinite ? max(0, canvasSize.width) : 0
        let canvasHeight = canvasSize.height.isFinite ? max(0, canvasSize.height) : 0
        let viewportWidth = viewportSize.width.isFinite ? max(0, viewportSize.width) : 0
        let viewportHeight = viewportSize.height.isFinite ? max(0, viewportSize.height) : 0
        let widthRatio = canvasWidth > 0 ? viewportWidth / canvasWidth : 1
        let scale = max(0.8, min(1, widthRatio))
        return SessionMapViewportGeometry(
            scale: scale,
            panBounds: CGSize(
                width: max(0, canvasWidth * scale - viewportWidth),
                height: max(0, canvasHeight * scale - viewportHeight)
            )
        )
    }

    private static func classifyBackEdges(
        graph: SessionMapGraph,
        rankEdgeIndices: [Int],
        nodeIDs: Set<String>
    ) -> Set<Int> {
        var adjacency: [String: [Int]] = [:]
        for index in rankEdgeIndices {
            adjacency[graph.edges[index].from, default: []].append(index)
        }
        for id in adjacency.keys {
            adjacency[id]?.sort { lhs, rhs in
                edgeComesBefore(
                    graph.edges[lhs], graph.edges[rhs],
                    lhsIndex: lhs, rhsIndex: rhs
                )
            }
        }

        var states: [String: Int] = [:]
        var backEdges: Set<Int> = []
        func visit(_ id: String) {
            states[id] = 1
            for index in adjacency[id, default: []] {
                let target = graph.edges[index].to
                if states[target] == 1 {
                    backEdges.insert(index)
                } else if states[target] == nil {
                    visit(target)
                }
            }
            states[id] = 2
        }
        for id in nodeIDs.sorted() where states[id] == nil {
            visit(id)
        }
        return backEdges
    }

    private static func longestPathRanks(
        graph: SessionMapGraph,
        rankEdgeIndices: [Int],
        backEdgeIndices: Set<Int>
    ) -> [String: Int] {
        let nodeIDs = graph.nodes.map(\.id)
        var indegrees = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, 0) })
        var outgoing: [String: [Int]] = [:]
        for index in rankEdgeIndices where !backEdgeIndices.contains(index) {
            let edge = graph.edges[index]
            indegrees[edge.to, default: 0] += 1
            outgoing[edge.from, default: []].append(index)
        }
        for id in outgoing.keys {
            outgoing[id]?.sort { lhs, rhs in
                edgeComesBefore(
                    graph.edges[lhs], graph.edges[rhs],
                    lhsIndex: lhs, rhsIndex: rhs
                )
            }
        }

        var ranks = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, 0) })
        var ready = nodeIDs.filter { indegrees[$0] == 0 }.sorted()
        while !ready.isEmpty {
            let id = ready.removeFirst()
            for index in outgoing[id, default: []] {
                let edge = graph.edges[index]
                ranks[edge.to] = max(ranks[edge.to, default: 0], ranks[id, default: 0] + 1)
                indegrees[edge.to, default: 0] -= 1
                if indegrees[edge.to] == 0 {
                    ready.append(edge.to)
                    ready.sort()
                }
            }
        }
        return ranks
    }

    private static func edgeComesBefore(
        _ lhs: SessionMapEdge,
        _ rhs: SessionMapEdge,
        lhsIndex: Int,
        rhsIndex: Int
    ) -> Bool {
        if lhs.from != rhs.from { return lhs.from < rhs.from }
        if lhs.to != rhs.to { return lhs.to < rhs.to }
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.label != rhs.label { return (lhs.label ?? "") < (rhs.label ?? "") }
        return lhsIndex < rhsIndex
    }

    private static func freeLabelFrame(
        for label: String?,
        center: CGPoint,
        nodeFrames: [CGRect],
        occupiedLabelFrames: [CGRect]
    ) -> CGRect? {
        guard let label, !label.isEmpty else { return nil }
        let width = min(112, max(36, CGFloat(label.count) * 7 + 12))
        let frame = CGRect(x: center.x - width / 2, y: center.y - 9, width: width, height: 18)
        guard !nodeFrames.contains(where: { $0.intersects(frame) }),
              !occupiedLabelFrames.contains(where: { $0.intersects(frame) })
        else { return nil }
        return frame
    }

    private static func appendGeometryDiagnostics(
        graph: SessionMapGraph,
        frames: [String: CGRect],
        routes: [SessionMapEdgeRoute],
        size: CGSize,
        to diagnostics: inout [SessionMapLayoutDiagnostic]
    ) {
        if frames.count != graph.nodes.count {
            appendDiagnostic(
                code: "missing-node-frame",
                message: "One or more graph nodes have no frame.",
                to: &diagnostics
            )
        }

        let orderedFrames = graph.nodes.compactMap { frames[$0.id] }
        for index in orderedFrames.indices {
            let frame = orderedFrames[index]
            if !frame.minX.isFinite || !frame.minY.isFinite
                || !frame.width.isFinite || !frame.height.isFinite
                || frame.minX < 0 || frame.minY < 0
                || frame.maxX > size.width || frame.maxY > size.height
            {
                appendDiagnostic(
                    code: "invalid-node-bounds",
                    message: "A node frame falls outside the canvas.",
                    to: &diagnostics
                )
            }
            for otherIndex in orderedFrames.indices where index < otherIndex {
                if frame.intersects(orderedFrames[otherIndex]) {
                    appendDiagnostic(
                        code: "node-overlap",
                        message: "Two node frames overlap.",
                        to: &diagnostics
                    )
                }
            }
        }
        for route in routes {
            let points = [route.start, route.end]
                + [route.controlPoint1, route.controlPoint2].compactMap { $0 }
                + route.sideLanePoints
            if points.contains(where: { !$0.x.isFinite || !$0.y.isFinite }) {
                appendDiagnostic(
                    code: "invalid-edge-route",
                    message: "An edge route contains a non-finite point.",
                    to: &diagnostics
                )
            }
            if let labelFrame = route.labelFrame,
               orderedFrames.contains(where: { $0.intersects(labelFrame) })
            {
                appendDiagnostic(
                    code: "edge-label-collision",
                    message: "An edge label overlaps a node frame.",
                    to: &diagnostics
                )
            }
        }
    }

    private static func appendDiagnostic(
        code: String,
        message: String,
        to diagnostics: inout [SessionMapLayoutDiagnostic]
    ) {
        guard diagnostics.count < maximumDiagnostics else { return }
        diagnostics.append(SessionMapLayoutDiagnostic(code: code, message: message))
    }
}
