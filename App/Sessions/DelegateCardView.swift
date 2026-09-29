import SwiftUI

struct DelegateCardView: View {
    let tool: ToolPresentation
    let workers: [SubagentPresentation]
    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var localChoice: Bool?

    var body: some View {
        CornerCard(color: accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if isExpanded {
                    expandedBody
                        .transition(isReduceMotionEnabled ? .identity : .opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var cardContent: ToolCardContent { tool.content }

    private var headerPresentation: ToolCardHeaderPresentation {
        ToolCardHeaderPresentation(
            content: cardContent,
            phase: tool.phase,
            duration: tool.phase == .running
                ? nil
                : tool.durationLabel().map(ToolCardDurationPresentation.label))
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tool.phase == .failed,
               !workers.isEmpty,
               let error = headerPresentation.displayedOutcome {
                Text(error)
                    .font(TenXTypography.body(size: 11, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if workers.isEmpty {
                ToolSurfaceView(
                    body: cardContent.body,
                    phase: tool.phase,
                    topFilePath: topFilePath)
            }
            ForEach(workers) { worker in
                SubagentCardView(presentation: worker, style: .worker)
            }
        }
    }

    private var topFilePath: String? {
        if case .file(let path, _) = cardContent.reference {
            return path
        }
        return nil
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                leadingContent(showsWorkerCount: true)
                Spacer(minLength: 8)
                statusContent
            }
            VStack(alignment: .leading, spacing: 5) {
                leadingContent(showsWorkerCount: false)
                HStack(spacing: 8) {
                    Text(workerCountLabel)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Spacer(minLength: 8)
                    statusContent
                }
            }
        }
    }

    private func leadingContent(showsWorkerCount: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 10)
                    Text(cardContent.verb)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                }
                .frame(minHeight: ToolCardScaffoldLayout.minimumDisclosureHitHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses delegate workers" : "Expands delegate workers")

            if let primary = cardContent.primary, !primary.isEmpty {
                Text(primary)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsWorkerCount {
                if headerPresentation.displayedOutcome != nil {
                    outcomeContent(includeSeparator: true)
                }
                Text("·")
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                Text(workerCountLabel)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func outcomeContent(includeSeparator: Bool) -> some View {
        if let outcome = headerPresentation.displayedOutcome {
            Text(includeSeparator ? "· \(outcome)" : outcome)
                .font(TenXTypography.body(size: 10, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if tool.phase == .running, tool.hasReliableStartDate {
            TimelineView(.periodic(from: tool.startDate, by: 1)) { context in
                statusContent(at: context.date)
            }
        } else {
            statusContent(at: tool.endDate ?? tool.startDate)
        }
    }

    private func statusContent(at date: Date) -> some View {
        HStack(spacing: 8) {
            Text(tool.phase.label)
                .foregroundStyle(accentColor)
            if let duration = tool.durationLabel(at: date) {
                Text(ToolCardDurationPresentation.label(duration))
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .help(ToolCardDurationPresentation.help)
            }
        }
        .font(TenXTypography.body(size: 10, weight: .medium))
    }

    private var workerCountLabel: String {
        switch workers.count {
        case 0: "No workers"
        case 1: "1 worker"
        default: "\(workers.count) workers"
        }
    }

    private var accessibilityLabel: String {
        var parts = [cardContent.verb]
        if let primary = cardContent.primary, !primary.isEmpty { parts.append(primary) }
        if let outcome = headerPresentation.displayedOutcome { parts.append(outcome) }
        parts.append(workerCountLabel)
        parts.append(tool.phase.label)
        if let duration = tool.durationLabel() {
            parts.append(ToolCardDurationPresentation.label(duration))
        }
        return parts.joined(separator: ", ")
    }

    private var isExpanded: Bool {
        disclosureState?.isExpanded(for: tool)
            ?? localChoice
            ?? ToolDetailMode.standard.isExpandedByDefault(tool.disclosureTraits)
    }

    private func toggle() {
        let update = {
            if let disclosureState {
                disclosureState.setExpanded(!isExpanded, for: tool)
            } else {
                localChoice = !isExpanded
            }
        }
        if isReduceMotionEnabled { update() }
        else { withAnimation(.easeInOut(duration: 0.14), update) }
    }

    private var accentColor: Color {
        switch tool.phase {
        case .failed:
            TenXPalette.color(TenXPalette.signalRedHex)
        case .interrupted:
            TenXPalette.color(TenXPalette.mutedTextHex)
        case .running, .complete:
            TenXPalette.color(TenXPalette.cyanHex)
        }
    }
}
