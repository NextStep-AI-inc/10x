import SwiftUI

struct SessionMapGraphView: View {
    let document: SessionMapDocument
    let layout: SessionMapLayoutResult
    @Binding var focus: SessionMapFocus
    let activity: SessionMapActivity
    let changes: SessionMapChanges
    let onAction: (SessionMapAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            graph
            if let selectedNode {
                selectedDetails(selectedNode)
            }
            relationshipList
        }
        .onChange(of: document) { oldDocument, newDocument in
            focus = SessionMapInteraction.reconciledFocus(
                focus, replacing: oldDocument, with: newDocument)
        }
    }

    static func measuredHeights(for graph: SessionMapGraph) -> [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: graph.nodes.map {
            ($0.id, SessionMapNodeView.measuredHeight(for: $0))
        })
    }

    private var graph: some View {
        GeometryReader { geometry in
            let viewport = SessionMapLayout.viewportGeometry(
                canvasSize: layout.size,
                viewportSize: geometry.size)
            ScrollView([.horizontal, .vertical]) {
                graphCanvas
                    .frame(width: layout.size.width, height: layout.size.height)
                    .scaleEffect(viewport.scale, anchor: .topLeading)
                    .frame(
                        width: layout.size.width * viewport.scale,
                        height: layout.size.height * viewport.scale,
                        alignment: .topLeading)
            }
            .scrollIndicators(viewport.panBounds.width > 0 || viewport.panBounds.height > 0 ? .visible : .hidden)
        }
        .frame(height: min(max(96, layout.size.height), 480))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Architecture diagram")
    }

    private var graphCanvas: some View {
        let highlightedNodeIDs = SessionMapInteraction.highlightedNodeIDs(
            graph: document.graph, focus: focus)
        return ZStack(alignment: .topLeading) {
            edgeCanvas(highlightedNodeIDs: highlightedNodeIDs)
            ForEach(document.graph.nodes) { node in
                if let frame = layout.frames[node.id] {
                    SessionMapNodeView(
                        node: node,
                        graph: document.graph,
                        isHighlighted: highlightedNodeIDs.contains(node.id),
                        isDimmed: !highlightedNodeIDs.isEmpty && !highlightedNodeIDs.contains(node.id),
                        isActive: activity.activeNodeIDs.contains(node.id),
                        changeKind: changeKind(for: node.id),
                        focus: $focus)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    private func edgeCanvas(highlightedNodeIDs: Set<String>) -> some View {
        let anchor = focus.hoveredNodeID ?? focus.focusedNodeID ?? focus.selectedNodeID
        return Canvas { context, _ in
            for route in layout.edges {
                let isHighlighted = anchor.map {
                    route.edge.from == $0 || route.edge.to == $0
                } ?? false
                let isDimmed = !highlightedNodeIDs.isEmpty && !isHighlighted
                let color = route.edge.kind == .data
                    ? TenXPalette.color(TenXPalette.mutedTextHex)
                    : TenXPalette.color(TenXPalette.interactiveCyanHex)
                var path = Path()
                path.move(to: route.start)
                if let first = route.controlPoint1, let second = route.controlPoint2 {
                    path.addCurve(to: route.end, control1: first, control2: second)
                } else {
                    for point in route.sideLanePoints { path.addLine(to: point) }
                    path.addLine(to: route.end)
                }
                context.stroke(
                    path,
                    with: .color(color.opacity(isDimmed ? 0.16 : 0.72)),
                    style: StrokeStyle(
                        lineWidth: isHighlighted ? 2 : 1,
                        dash: route.isBackEdge ? [4, 3] : []))
                drawArrow(route: route, color: color.opacity(isDimmed ? 0.16 : 0.72), in: &context)
                if let label = route.edge.label, let frame = route.labelFrame {
                    context.draw(
                        Text(label)
                            .font(TenXTypography.body(size: 9))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex)),
                        at: CGPoint(x: frame.midX, y: frame.midY))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawArrow(
        route: SessionMapEdgeRoute,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let previous = route.sideLanePoints.last ?? route.controlPoint2 ?? route.start
        let angle = atan2(route.end.y - previous.y, route.end.x - previous.x)
        let length: CGFloat = 6
        var arrow = Path()
        arrow.move(to: route.end)
        arrow.addLine(to: CGPoint(
            x: route.end.x - length * cos(angle - .pi / 6),
            y: route.end.y - length * sin(angle - .pi / 6)))
        arrow.move(to: route.end)
        arrow.addLine(to: CGPoint(
            x: route.end.x - length * cos(angle + .pi / 6),
            y: route.end.y - length * sin(angle + .pi / 6)))
        context.stroke(arrow, with: .color(color), lineWidth: 1)
    }

    @ViewBuilder private func selectedDetails(_ node: SessionMapNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.label)
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                Text(node.status.displayName)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            if let note = node.note {
                Text(note)
                    .font(TenXTypography.body(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 4) {
                if let ref = node.ref {
                    Button("Jump") { onAction(.jump(ref: ref)) }
                        .buttonStyle(GhostActionStyle())
                }
                if let file = node.file {
                    Button("Open \(file.split(separator: "/").last.map(String.init) ?? file)") {
                        onAction(.openFile(path: file))
                    }
                    .buttonStyle(GhostActionStyle())
                    .accessibilityLabel("Open file \(file)")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .accessibilityElement(children: .contain)
    }

    private var relationshipList: some View {
        DisclosureGroup("Relationships") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(document.graph.nodes) { node in
                    Text(SessionMapInteraction.accessibilityLabel(
                        for: node,
                        graph: document.graph,
                        isActive: activity.activeNodeIDs.contains(node.id)))
                        .font(TenXTypography.body(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
        .font(TenXTypography.body(size: 12, weight: .medium))
        .accessibilityLabel("Architecture relationships")
    }

    private var selectedNode: SessionMapNode? {
        guard let id = focus.selectedNodeID else { return nil }
        return document.graph.nodes.first(where: { $0.id == id })
    }

    private func changeKind(for nodeID: String) -> SessionMapNodeChangeKind? {
        if changes.addedNodeIDs.contains(nodeID) { return .added }
        if changes.changedNodeIDs.contains(nodeID) { return .changed }
        if changes.removedNodeIDs.contains(nodeID) { return .removed }
        return nil
    }
}
