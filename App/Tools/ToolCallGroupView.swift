import SwiftUI

struct ToolCallGroupHeaderPresentation: Equatable, Sendable {
    let title: String
    let info: String?
    let usesInlineToolInfo: Bool

    init(group: TranscriptToolGroup, mode: ToolDetailMode) {
        usesInlineToolInfo = mode == .slim
        if mode == .slim {
            if group.tools.count == 1, let tool = group.tools.first {
                title = tool.content.verb
                info = Self.lineInfo(for: tool)
            } else {
                title = group.tools.map { tool in
                    if let info = Self.lineInfo(for: tool) {
                        return "\(tool.content.verb) \(info)"
                    }
                    return tool.content.verb
                }.joined(separator: " · ")
                info = nil
            }
        } else {
            title = group.tools.count == 1 ? "Tool call" : "Tool calls (\(group.tools.count))"
            info = nil
        }
    }

    private static func lineInfo(for tool: ToolPresentation) -> String? {
        guard let primary = tool.content.primary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !primary.isEmpty
        else { return nil }
        return primary
    }
}

struct ToolCallGroupView: View {
    let group: TranscriptToolGroup
    @Environment(\.toolDisclosureState) private var disclosureState
    @State private var localChoice: Bool?

    var body: some View {
        header
    }

    private var header: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 10)
                titleContent
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

    @ViewBuilder
    private var titleContent: some View {
        let presentation = headerPresentation
        if presentation.usesInlineToolInfo, group.tools.count == 1, let tool = group.tools.first {
            Text(presentation.title)
                .font(TenXTypography.body(size: 12, weight: .semibold))
            if let reference = tool.content.reference {
                TranscriptReferenceView(reference: reference)
            } else if let info = presentation.info {
                Text(info)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(presentation.title)
                .font(TenXTypography.body(size: 12, weight: .semibold))
        }
    }

    private var headerPresentation: ToolCallGroupHeaderPresentation {
        ToolCallGroupHeaderPresentation(group: group, mode: currentMode)
    }

    private var toolDescription: String {
        group.tools.count == 1 ? "tool call" : "tool calls"
    }

    private var accessibilityLabel: String {
        let info = headerPresentation.info.map { ", \($0)" } ?? ""
        return group.tools.count == 1
            ? "\(headerPresentation.title)\(info), \(group.phase.label)"
            : "\(headerPresentation.title), \(group.phase.label)"
    }

    private var currentMode: ToolDetailMode {
        disclosureState?.mode ?? .standard
    }

    private var isExpanded: Bool {
        disclosureState?.isGroupExpanded(id: group.id)
            ?? localChoice
            ?? currentMode.opensGroupsByDefault
    }

    private func toggle() {
        if let disclosureState {
            disclosureState.setGroupExpanded(!isExpanded, id: group.id)
        } else {
            localChoice = !isExpanded
        }
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
