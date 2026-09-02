import SwiftUI

struct ToolCardHeaderPresentation: Equatable, Sendable {
    let content: ToolCardContent
    let phase: ToolPhase
    let duration: String

    var visibleText: String {
        var value = content.verb
        if let primary = content.primary, !primary.isEmpty { value += " \(primary)" }
        if let displayedOutcome { value += " · \(displayedOutcome)" }
        return value
    }

    var accessibilityLabel: String {
        var leading = content.verb
        if let primary = content.primary, !primary.isEmpty { leading += " \(primary)" }
        var parts = [leading]
        if let displayedOutcome { parts.append(displayedOutcome) }
        parts.append(phase.label)
        parts.append(accessibleDuration)
        return parts.joined(separator: ", ")
    }

    var displayedOutcome: String? {
        guard let outcome = content.outcome?.trimmingCharacters(in: .whitespacesAndNewlines),
              !outcome.isEmpty,
              outcome.caseInsensitiveCompare(phase.label) != .orderedSame
        else { return nil }
        return outcome
    }

    private var accessibleDuration: String {
        guard duration.hasSuffix("s") else { return duration }
        return "\(duration.dropLast()) seconds"
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
            duration: presentation.durationLabel)
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
                    if let outcome = headerPresentation.displayedOutcome {
                        Text(outcome)
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

            if showsOutcome, let outcome = headerPresentation.displayedOutcome {
                Text("· \(outcome)")
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            Text(presentation.phase.label)
                .foregroundStyle(accentColor)
            Text(presentation.durationLabel)
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .font(TenXTypography.body(size: 10, weight: .medium))
    }

    private var isExpanded: Bool {
        disclosureState?.isExpanded(for: presentation)
            ?? localChoice
            ?? ToolDetailMode.auto.isExpandedByDefault(presentation.disclosureTraits)
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
        TenXPalette.color(presentation.isError
            ? TenXPalette.signalRedHex
            : TenXPalette.cyanHex)
    }
}
