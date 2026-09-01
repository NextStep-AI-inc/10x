import SwiftUI

struct ToolCallGroupView: View {
    let group: TranscriptToolGroup
    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var localChoice: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.tools) { tool in
                        ToolCardView(presentation: tool)
                    }
                }
                .transition(isReduceMotionEnabled ? .identity : .opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 10)
                Text(title)
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                Text(group.phase.label)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            .frame(minHeight: ToolCardScaffoldLayout.minimumDisclosureHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapses \(toolDescription)" : "Expands \(toolDescription)")
    }

    private var title: String {
        group.tools.count == 1 ? "Tool call" : "Tool calls (\(group.tools.count))"
    }

    private var toolDescription: String {
        group.tools.count == 1 ? "tool call" : "tool calls"
    }

    private var accessibilityLabel: String {
        group.tools.count == 1
            ? "Tool call, \(group.phase.label)"
            : "\(group.tools.count) tool calls, \(group.phase.label)"
    }

    private var isExpanded: Bool {
        disclosureState?.isGroupExpanded(id: group.id) ?? localChoice ?? true
    }

    private func toggle() {
        let update = {
            if let disclosureState {
                disclosureState.setGroupExpanded(!isExpanded, id: group.id)
            } else {
                localChoice = !isExpanded
            }
        }
        if isReduceMotionEnabled { update() }
        else { withAnimation(.easeInOut(duration: 0.14), update) }
    }

    private var statusColor: Color {
        switch group.phase {
        case .complete:
            TenXPalette.color(TenXPalette.mutedTextHex)
        case .running:
            TenXPalette.color(TenXPalette.cyanHex)
        case .failed:
            TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}
