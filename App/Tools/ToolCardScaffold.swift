import SwiftUI

struct ToolCardDiffTotals: Equatable, Sendable {
    let additions: Int
    let removals: Int

    var summary: String { "+\(additions) −\(removals)" }
}

struct ToolCardHeaderPresentation: Equatable, Sendable {
    let content: ToolCardContent
    let phase: ToolPhase
    let duration: String?
    let diffTotals: ToolCardDiffTotals?

    init(content: ToolCardContent, phase: ToolPhase, duration: String?) {
        self.content = content
        self.phase = phase
        self.duration = duration
        diffTotals = content.body.diffTotals
    }

    var visibleText: String {
        var value = content.verb
        if let primary = content.primary, !primary.isEmpty { value += " \(primary)" }
        if let displayedOutcomeText { value += " · \(displayedOutcomeText)" }
        return value
    }

    var accessibilityLabel: String {
        var leading = content.verb
        if let primary = content.primary, !primary.isEmpty { leading += " \(primary)" }
        var parts = [leading]
        if let displayedOutcomeText { parts.append(displayedOutcomeText) }
        parts.append(phase.label)
        if let accessibleDuration { parts.append(accessibleDuration) }
        return parts.joined(separator: ", ")
    }

    var displayedOutcome: String? {
        guard let outcome = content.outcome?.trimmingCharacters(in: .whitespacesAndNewlines),
              !outcome.isEmpty,
              outcome.caseInsensitiveCompare(phase.label) != .orderedSame
        else { return nil }
        return outcome
    }

    var displayedOutcomeText: String? {
        diffTotals?.summary ?? displayedOutcome
    }

    private var accessibleDuration: String? {
        guard let duration else { return nil }
        guard duration.hasSuffix("s") else { return duration }
        return "\(duration.dropLast()) seconds"
    }
}

private extension ToolBody {
    var diffTotals: ToolCardDiffTotals? {
        switch self {
        case .diff(let diff, _):
            return ToolCardDiffTotals(
                additions: diff.files.reduce(0) { $0 + $1.additions },
                removals: diff.files.reduce(0) { $0 + $1.removals })
        case .stack(let bodies):
            let totals = bodies.compactMap(\.diffTotals)
            guard !totals.isEmpty else { return nil }
            return ToolCardDiffTotals(
                additions: totals.reduce(0) { $0 + $1.additions },
                removals: totals.reduce(0) { $0 + $1.removals })
        default:
            return nil
        }
    }
}

enum ToolCardDurationPresentation {
    static let help = "Total time from tool dispatch to completion. Process wall time in command output may be shorter."

    static func label(_ duration: String) -> String {
        "Total \(duration)"
    }
}

enum ToolCardScaffoldLayout {
    static let minimumDisclosureHitHeight: CGFloat = 32
}

struct ToolCardScaffold<Content: View>: View {
    let presentation: ToolPresentation
    let cardContent: ToolCardContent
    let details: Content
    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var localChoice: Bool?

    init(
        presentation: ToolPresentation,
        cardContent: ToolCardContent,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.cardContent = cardContent
        details = content()
    }

    var body: some View {
        CornerCard(color: accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if isExpanded {
                    details
                        .transition(isReduceMotionEnabled ? .identity : .opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerPresentation.accessibilityLabel)
    }

    private var headerPresentation: ToolCardHeaderPresentation {
        ToolCardHeaderPresentation(
            content: cardContent,
            phase: presentation.phase,
            duration: presentation.phase == .running
                ? nil
                : presentation.durationLabel().map(ToolCardDurationPresentation.label))
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                leadingContent(showsOutcome: true)
                Spacer(minLength: 8)
                statusContent
            }
            VStack(alignment: .leading, spacing: 5) {
                leadingContent(showsOutcome: false)
                HStack(spacing: 8) {
                    outcomeContent(includeSeparator: false)
                    Spacer(minLength: 8)
                    statusContent
                }
                .font(TenXTypography.body(size: 10, weight: .medium))
            }
        }
    }

    private func leadingContent(showsOutcome: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: toggle) {
                // Baseline-align so the button reports the verb's text baseline,
                // not the smaller chevron's — the row anchors on this guide.
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
            .accessibilityLabel(headerPresentation.accessibilityLabel)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses tool details" : "Expands tool details")

            if let reference = cardContent.reference {
                TranscriptReferenceView(reference: reference)
            } else if let primary = cardContent.primary, !primary.isEmpty {
                Text(primary)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsOutcome {
                outcomeContent(includeSeparator: true)
            }
        }
    }

    @ViewBuilder
    private func outcomeContent(includeSeparator: Bool) -> some View {
        if let totals = headerPresentation.diffTotals {
            if includeSeparator {
                Text("·")
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            HStack(spacing: 3) {
                Text("+\(totals.additions)")
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                Text("−\(totals.removals)")
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
            .font(TenXTypography.mono(size: 10, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        } else if let outcome = headerPresentation.displayedOutcome {
            Text(includeSeparator ? "· \(outcome)" : outcome)
                .font(TenXTypography.body(size: 10, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if presentation.phase == .running, presentation.hasReliableStartDate {
            TimelineView(.periodic(from: presentation.startDate, by: 1)) { context in
                statusContent(at: context.date)
            }
        } else {
            statusContent(at: presentation.endDate ?? presentation.startDate)
        }
    }

    private func statusContent(at date: Date) -> some View {
        HStack(spacing: 8) {
            Text(presentation.phase.label)
                .foregroundStyle(accentColor)
            if let duration = presentation.durationLabel(at: date) {
                Text(ToolCardDurationPresentation.label(duration))
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .help(ToolCardDurationPresentation.help)
            }
        }
        .font(TenXTypography.body(size: 10, weight: .medium))
    }

    private var isExpanded: Bool {
        disclosureState?.isExpanded(for: presentation)
            ?? localChoice
            ?? ToolDetailMode.standard.isExpandedByDefault(presentation.disclosureTraits)
    }

    private func toggle() {
        let update = {
            if let disclosureState {
                disclosureState.setExpanded(!isExpanded, for: presentation)
            } else {
                localChoice = !isExpanded
            }
        }
        if isReduceMotionEnabled { update() }
        else { withAnimation(.easeInOut(duration: 0.14), update) }
    }

    private var accentColor: Color {
        switch presentation.phase {
        case .failed:
            TenXPalette.color(TenXPalette.signalRedHex)
        case .interrupted:
            TenXPalette.color(TenXPalette.mutedTextHex)
        case .running, .complete:
            TenXPalette.color(TenXPalette.cyanHex)
        }
    }
}
