import SwiftUI

struct SubagentCardView: View {
    let presentation: SubagentPresentation
    @Environment(\.toolDisclosureState) private var disclosureState
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
                disclosureState?.isExpanded(
                    id: presentation.id,
                    defaultValue: presentation.status.isActive || presentation.status.isError)
                    ?? localChoice
                    ?? presentation.status.isActive
                    || presentation.status.isError
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
