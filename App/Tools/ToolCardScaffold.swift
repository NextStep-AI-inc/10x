import AppKit
import SwiftUI

struct ToolCardScaffold<Content: View>: View {
    let presentation: ToolPresentation
    let title: String
    let subtitle: String?
    let fileReference: TranscriptReference?
    let content: Content
    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var localChoice: Bool?

    init(
        presentation: ToolPresentation,
        title: String,
        subtitle: String? = nil,
        fileReference: TranscriptReference? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.title = title
        self.subtitle = subtitle
        self.fileReference = fileReference
        self.content = content()
    }

    var body: some View {
        CornerCard(color: accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(action: toggle) {
                        HStack(spacing: 8) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(accentColor)
                                .frame(width: 10)
                            Text(title)
                                .font(TenXTypography.body(size: 12, weight: .semibold))
                            if fileReference == nil, let subtitle {
                                Text(subtitle)
                                    .font(TenXTypography.mono(size: 10))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                    .lineLimit(1)
                            }
                        }
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(presentation.phase.label)")
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    .accessibilityHint(isExpanded ? "Collapses tool details" : "Expands tool details")

                    if let fileReference {
                        TranscriptReferenceView(reference: fileReference)
                    }

                    Spacer(minLength: 8)
                    Text(presentation.phase.label)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(accentColor)
                    Text(presentation.durationLabel)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }

                if isExpanded {
                    content
                        .transition(isReduceMotionEnabled ? .identity : .opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(presentation.phase.label)")
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
