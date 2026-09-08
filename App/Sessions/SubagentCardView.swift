import SwiftUI

struct SubagentCardView: View {
    let presentation: SubagentPresentation
    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.openReportedSession) private var openReportedSession
    @State private var localChoice: Bool?

    init(presentation: SubagentPresentation) { self.presentation = presentation }

    var body: some View {
        CornerCard(color: accentColor) {
            DisclosureGroup(isExpanded: binding) {
                detail
                    .padding(.top, 10)
            } label: {
                HStack(spacing: 8) {
                    Text(presentation.agent.capitalized)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                    Text(presentation.task)
                        .font(TenXTypography.body(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Spacer(minLength: 12)
                    if let model = presentation.actualModel {
                        Text(model)
                            .font(TenXTypography.mono(size: 10))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    Text(presentation.status.label)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(accentColor)
                }
            }
            .disclosureGroupStyle(.automatic)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(presentation.agent) subagent, \(presentation.status.label)")
    }

    private var binding: Binding<Bool> {
        Binding(
            get: {
                disclosureState?.isExpanded(for: presentation)
                    ?? localChoice
                    ?? ToolDetailMode.standard.isExpandedByDefault(presentation.disclosureTraits)
            },
            set: { value in
                if let disclosureState { disclosureState.setExpanded(value, id: presentation.id) }
                else { localChoice = value }
            })
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            let metadata = metadataText
            if !metadata.isEmpty {
                Text(metadata)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            if let description = presentation.description,
               description != presentation.task {
                Text(description)
                    .font(TenXTypography.body(size: 11))
            }
            if let currentTool = presentation.currentTool {
                Text("Working in \(currentTool)")
                    .font(TenXTypography.body(size: 11, weight: .medium))
            }
            let recentTools = presentation.recentToolSummaries
            if !recentTools.isEmpty {
                Text("Recent tools")
                    .font(TenXTypography.body(size: 11, weight: .medium))
                ForEach(recentTools.indices, id: \.self) { index in
                    Text(recentTools[index])
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                }
            }
            ForEach(presentation.recentOutput, id: \.self) { output in
                Text(output)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if let result = presentation.resultText {
                Divider()
                Text(result)
                    .font(TenXTypography.body(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let sessionPath = presentation.reportedSessionPath {
                Button("Open session") {
                    Task { await openReportedSession(sessionPath) }
                }
                .buttonStyle(GhostActionStyle(horizontalPadding: 0))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataText: String {
        var values: [String] = []
        if let role = presentation.modelRole { values.append(role.capitalized) }
        if let thinking = presentation.thinkingLevel { values.append(thinking.capitalized) }
        if presentation.toolCount > 0 { values.append("\(presentation.toolCount) tools") }
        if let tokens = presentation.tokens { values.append("\(tokens.formatted()) tokens") }
        values.append(String(format: "%.1fs", presentation.durationMilliseconds / 1_000))
        return values.joined(separator: " · ")
    }

    private var accentColor: Color {
        TenXPalette.color(presentation.status.isError
            ? TenXPalette.signalRedHex
            : TenXPalette.cyanHex)
    }
}

struct OpenReportedSessionAction: Sendable {
    private let action: @MainActor @Sendable (String) async -> Void

    init(_ action: @escaping @MainActor @Sendable (String) async -> Void = { _ in }) {
        self.action = action
    }

    @MainActor
    func callAsFunction(_ path: String) async {
        await action(path)
    }
}

private struct OpenReportedSessionKey: EnvironmentKey {
    static let defaultValue = OpenReportedSessionAction()
}

extension EnvironmentValues {
    var openReportedSession: OpenReportedSessionAction {
        get { self[OpenReportedSessionKey.self] }
        set { self[OpenReportedSessionKey.self] = newValue }
    }
}
