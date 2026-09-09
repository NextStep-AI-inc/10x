import SwiftUI

struct SessionMapPaneView: View {
    static let contentPadding: CGFloat = 16

    @Bindable var model: SessionMapPaneModel
    var activity: SessionMapActivity = .empty
    var changes: SessionMapChanges = .empty
    var firstSeenOrder: [String]? = nil
    var updatedAt: Date?
    var attribution: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let document = model.displayedDocument {
                        headline(document)
                        activityLine
                        graph(document)
                        walkthrough(document)
                        plan(document)
                        summary(document)
                        supportingBlocks(document)
                    } else {
                        activityLine
                        emptyContent
                    }
                }
                .padding(Self.contentPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
            if let attribution = attribution ?? model.attribution,
               model.displayedDocument != nil
            {
                Text(attribution)
                    .font(TenXTypography.body(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: model.paneWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TenXPalette.color(TenXPalette.canvasHex))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Map")
                .font(TenXTypography.accent(size: 16))
            Spacer()
            Button("Settings", systemImage: "gearshape") { model.openSettings() }
                .labelStyle(.iconOnly)
                .buttonStyle(GhostActionStyle(horizontalPadding: 6))
                .accessibilityLabel("Map settings")
            Button("Close", systemImage: "xmark") { model.close() }
                .labelStyle(.iconOnly)
                .buttonStyle(GhostActionStyle(horizontalPadding: 6))
                .accessibilityLabel("Close map")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func headline(_ document: SessionMapDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.headline)
                .font(TenXTypography.accent(size: 16))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(phaseName(document.phase))
                if let updatedAt = updatedAt ?? model.updatedAt {
                    Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            .font(TenXTypography.body(size: 10, weight: .medium))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    @ViewBuilder private var activityLine: some View {
        if let status = statusPresentation {
            Label(status.text, systemImage: status.icon)
                .font(TenXTypography.body(size: 11, weight: .medium))
                .foregroundStyle(status.color)
                .fixedSize(horizontal: false, vertical: true)
        } else if let description = activity.unmappedDescriptions.first {
            Label(description, systemImage: "hammer")
                .font(TenXTypography.body(size: 11, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    @ViewBuilder private func graph(_ document: SessionMapDocument) -> some View {
        if !document.graph.nodes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        architectureTitle
                        Spacer()
                        graphLegend
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        architectureTitle
                        graphLegend
                    }
                }
                SessionMapGraphView(
                    document: document,
                    layout: SessionMapLayout.layout(
                        graph: document.graph,
                        firstSeenOrder: firstSeenOrder ?? model.firstSeenOrder,
                        measuredHeights: SessionMapGraphView.measuredHeights(for: document.graph)),
                    focus: $model.focus,
                    activity: activity,
                    changes: changes,
                    onAction: model.perform)
            }
        }
    }

    private var architectureTitle: some View {
        Text("Architecture")
            .font(TenXTypography.accent(size: 16))
    }

    private var graphLegend: some View {
        Text("Exists · Proposed · Planned · Active · Done · Failed")
            .font(TenXTypography.body(size: 9))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func walkthrough(_ document: SessionMapDocument) -> some View {
        if let flow = document.flow {
            SessionMapWalkthroughView(flow: flow, focus: $model.focus, onAction: model.perform)
        }
    }

    @ViewBuilder private func plan(_ document: SessionMapDocument) -> some View {
        if let plan = document.plan {
            SessionMapPlanView(plan: plan, focus: $model.focus, onAction: model.perform)
        }
    }

    @ViewBuilder private func summary(_ document: SessionMapDocument) -> some View {
        if let summary = document.summary {
            ContentDocumentView(
                document: MessageContentParser.parse(summary),
                spacing: 6,
                bodySize: 12)
        }
    }

    @ViewBuilder private func supportingBlocks(_ document: SessionMapDocument) -> some View {
        ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
            SessionMapSupportingBlockView(block: block, onAction: model.perform)
        }
    }

    @ViewBuilder private var emptyContent: some View {
        switch model.state {
        case .empty:
            stateMessage("Nothing new", detail: "The session has no new work to map.")
        case .needsGeneration:
            stateAction("Create a map from this session.", title: "Create map") {
                model.generate(.sinceCaughtUp)
            }
        case .writing:
            VStack(alignment: .leading, spacing: 10) {
                graphSkeleton
                Text("Building the first map from the current session.")
                    .font(TenXTypography.body(size: 12))
            }
        case .failed:
            stateAction("The map couldn’t be updated.", title: "Try again") {
                model.regenerate(.sinceCaughtUp)
            }
        case .needsModel:
            stateAction("Choose a model before creating a map.", title: "Choose a model in Settings") {
                model.openSettings()
            }
        case .ready, .checking, .stale:
            stateMessage("Map unavailable", detail: "Create the map again to restore this view.")
        }
    }

    private var graphSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(TenXPalette.color(TenXPalette.hoverNeutralHex))
            RoundedRectangle(cornerRadius: 6).fill(TenXPalette.color(TenXPalette.hoverNeutralHex))
        }
        .frame(height: 74)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.retainedFailureMessage {
                Text(message)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .accessibilityIdentifier("session-map-save-error")
            }
            HStack(spacing: 6) {
            if model.displayedDocument != nil {
                Menu("Regenerate") {
                    Button("Since caught up") { model.regenerate(.sinceCaughtUp) }
                    Button("Recent 3 turns") { model.regenerate(.recentThreeTurns) }
                    Button("Whole session") { model.regenerate(.wholeSession) }
                }
                .menuStyle(.borderlessButton)
                Button("Caught up") { model.caughtUp() }
                    .buttonStyle(GhostActionStyle())
            }
            Spacer()
            if model.state == .stale {
                Button("Update") { model.generate(.sinceCaughtUp) }
                    .buttonStyle(GhostActionStyle())
            } else if case .failed = model.state, model.displayedDocument != nil {
                Button("Try again") { model.regenerate(.sinceCaughtUp) }
                    .buttonStyle(GhostActionStyle())
            }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private func stateMessage(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(TenXTypography.accent(size: 16))
            Text(detail).font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    private func stateAction(_ text: String, title: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(TenXTypography.body(size: 12))
            Button(title, action: action).buttonStyle(GhostActionStyle())
        }
    }

    private var statusPresentation: (text: String, icon: String, color: Color)? {
        switch model.state {
        case .writing:
            ("Updating map…", "arrow.triangle.2.circlepath", TenXPalette.color(TenXPalette.mutedTextHex))
        case .checking:
            ("Checking layout…", "checkmark.circle", TenXPalette.color(TenXPalette.mutedTextHex))
        case .stale:
            ("New work is available.", "clock.arrow.circlepath", TenXPalette.color(TenXPalette.yellowHex))
        case .failed where model.displayedDocument != nil:
            ("The latest update failed. This map may be out of date.", "exclamationmark.triangle", TenXPalette.color(TenXPalette.signalRedHex))
        default:
            nil
        }
    }

    private func phaseName(_ phase: SessionMapPhase) -> String {
        switch phase {
        case .planning: "Planning"
        case .implementing: "Implementing"
        case .mixed: "Mixed"
        }
    }
}
