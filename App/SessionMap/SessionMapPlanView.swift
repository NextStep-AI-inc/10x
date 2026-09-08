import SwiftUI

struct SessionMapPlanView: View {
    let plan: SessionMapPlan
    @Binding var focus: SessionMapFocus
    let onAction: (SessionMapAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(plan.title)
                .font(TenXTypography.accent(size: 16))
            ForEach(Array(plan.tasks.enumerated()), id: \.offset) { _, task in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: iconName(for: task.status))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color(for: task.status))
                        .frame(width: 13, height: 18)
                    Button {
                        focus.selectedNodeID = task.node
                    } label: {
                        Text(task.text)
                            .font(TenXTypography.body(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(task.node == nil)
                    .onHover { isInside in
                        if isInside {
                            focus.hoveredNodeID = task.node
                        } else if focus.hoveredNodeID == task.node {
                            focus.hoveredNodeID = nil
                        }
                    }
                    if let ref = task.ref {
                        Button("Jump") { onAction(.jump(ref: ref)) }
                            .buttonStyle(GhostActionStyle(horizontalPadding: 4))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func iconName(for status: SessionMapPlanTaskStatus) -> String {
        switch status {
        case .todo: "circle"
        case .active: "circle.fill"
        case .done: "checkmark.circle.fill"
        case .blocked: "exclamationmark.circle.fill"
        }
    }

    private func color(for status: SessionMapPlanTaskStatus) -> Color {
        switch status {
        case .todo: TenXPalette.color(TenXPalette.mutedTextHex)
        case .active: TenXPalette.color(TenXPalette.cyanHex)
        case .done: TenXPalette.color(TenXPalette.interactiveCyanHex)
        case .blocked: TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}
