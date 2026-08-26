import AppKit
import SwiftUI

struct ToolCardHeaderPresentation: Equatable, Sendable {
    let content: ToolCardContent
    let phase: ToolPhase
    let duration: String

    var visibleText: String {
        var value = content.verb
        if let primary = content.primary, !primary.isEmpty { value += " \(primary)" }
        if let outcome = content.outcome, !outcome.isEmpty { value += " · \(outcome)" }
        return value
    }

    var accessibilityLabel: String {
        var leading = content.verb
        if let primary = content.primary, !primary.isEmpty { leading += " \(primary)" }
        var parts = [leading]
        if let outcome = content.outcome, !outcome.isEmpty { parts.append(outcome) }
        parts.append(phase.label)
        parts.append(accessibleDuration)
        return parts.joined(separator: ", ")
    }

    private var accessibleDuration: String {
        guard duration.hasSuffix("s") else { return duration }
        return "\(duration.dropLast()) seconds"
    }
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

    init(
        presentation: ToolPresentation,
        title: String,
        subtitle: String? = nil,
        fileReference: TranscriptReference? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        cardContent = ToolCardContent(
            title: title,
            verb: title,
            primary: subtitle,
            outcome: nil,
            reference: fileReference,
            body: .empty(""))
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
                    if let outcome = cardContent.outcome, !outcome.isEmpty {
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
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 10)
                    Text(cardContent.verb)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                }
                .frame(minHeight: 28)
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

            if showsOutcome, let outcome = cardContent.outcome, !outcome.isEmpty {
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
            ?? ToolDisclosureState.defaultExpanded(for: presentation)
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

struct BoundedToolOutputView: View {
    let text: String
    let lineLimit: Int
    let emptyText: String?
    let font: Font
    let color: Color
    let isDisclosureAlwaysAvailable: Bool
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var isExpanded = false

    init(
        text: String,
        lineLimit: Int,
        emptyText: String? = nil,
        font: Font,
        color: Color = TenXPalette.color(TenXPalette.nearBlackHex),
        isDisclosureAlwaysAvailable: Bool = false
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.emptyText = emptyText
        self.font = font
        self.color = color
        self.isDisclosureAlwaysAvailable = isDisclosureAlwaysAvailable
    }

    @ViewBuilder
    var body: some View {
        if text.isEmpty {
            if let emptyText {
                Text(emptyText)
                    .font(font)
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(isExpanded ? nil : lineLimit)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    if Self.shouldOfferDisclosure(
                        text,
                        lineLimit: lineLimit,
                        isAlwaysAvailable: isDisclosureAlwaysAvailable
                    ) {
                        Button(isExpanded ? "Show less" : "Show all", action: toggle)
                            .buttonStyle(GhostActionStyle())
                    }
                    Button("Copy", action: copy)
                        .buttonStyle(GhostActionStyle())
                }
                .font(TenXTypography.body(size: 10, weight: .medium))
            }
        }
    }

    nonisolated static func shouldOfferDisclosure(
        _ text: String,
        lineLimit: Int,
        isAlwaysAvailable: Bool = false
    ) -> Bool {
        isAlwaysAvailable
            || text.split(separator: "\n", omittingEmptySubsequences: false).count > lineLimit
            || text.count > lineLimit * 120
    }

    private func toggle() {
        let update = { isExpanded.toggle() }
        if isReduceMotionEnabled { update() }
        else { withAnimation(.easeInOut(duration: 0.14), update) }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
