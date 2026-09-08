import AppKit
import SwiftUI

struct SessionMapNodeView: View {
    let node: SessionMapNode
    let graph: SessionMapGraph
    let isHighlighted: Bool
    let isDimmed: Bool
    let isActive: Bool
    let changeKind: SessionMapNodeChangeKind?
    @Binding var focus: SessionMapFocus

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.sessionMapReduceMotionOverride) private var reduceMotionOverride
    @FocusState private var isKeyboardFocused: Bool
    @State private var isPulseVisible = false

    private var isReduceMotionEnabled: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    var body: some View {
        Button {
            select()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(node.label)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isActive {
                        Circle()
                            .fill(TenXPalette.color(TenXPalette.cyanHex))
                            .frame(width: 6, height: 6)
                            .opacity(isPulseVisible ? 0.35 : 1)
                            .animation(
                                isReduceMotionEnabled
                                    ? nil
                                    : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: isPulseVisible)
                            .accessibilityHidden(true)
                    }
                }
                Text(subtitle)
                    .font(TenXTypography.body(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    statusMark
                    Text(node.status.displayName)
                        .font(TenXTypography.body(size: 9, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($isKeyboardFocused)
        .onKeyPress(
            keys: [.return, .space],
            phases: .down,
            action: handleActivationKey)
        .background(backgroundColor)
        .overlay(border)
        .onHover { isInside in
            if isInside {
                focus.hoveredNodeID = node.id
            } else if focus.hoveredNodeID == node.id {
                focus.hoveredNodeID = nil
            }
        }
        .onChange(of: isKeyboardFocused) { _, isFocused in
            if isFocused {
                focus.focusedNodeID = node.id
            } else if focus.focusedNodeID == node.id {
                focus.focusedNodeID = nil
            }
        }
        .onAppear {
            if isActive && !isReduceMotionEnabled {
                isPulseVisible = true
            }
        }
        .onChange(of: isReduceMotionEnabled) { _, isReduced in
            isPulseVisible = isActive && !isReduced
        }
        .onChange(of: isActive) { _, isNowActive in
            isPulseVisible = isNowActive && !isReduceMotionEnabled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SessionMapInteraction.accessibilityLabel(
            for: node, graph: graph, isActive: isActive))
        .accessibilityHint("Select this component to show its details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select() }
    }

    private func select() { focus.selectedNodeID = node.id }

    private func handleActivationKey(_: KeyPress) -> KeyPress.Result {
        select()
        return .handled
    }

    static func measuredHeight(for node: SessionMapNode, width: CGFloat = 124) -> CGFloat {
        let textWidth = max(1, width - 34)
        let label = NSAttributedString(
            string: node.label,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        let labelHeight = ceil(label.boundingRect(
            with: CGSize(width: textWidth, height: 2_048),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let subtitle = NSAttributedString(
            string: renderedSubtitle(for: node),
            attributes: [.font: NSFont.systemFont(ofSize: 10)])
        let subtitleHeight = ceil(subtitle.boundingRect(
            with: CGSize(width: width - 18, height: 2_048),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let statusHeight = ceil(NSFont.systemFont(ofSize: 9, weight: .medium).boundingRectForFont.height)
        return max(64, 24 + labelHeight + subtitleHeight + statusHeight)
    }

    private var subtitle: String {
        Self.renderedSubtitle(for: node)
    }

    static func renderedSubtitle(for node: SessionMapNode) -> String {
        if let group = node.group { return "\(node.kind.displayName) · \(group)" }
        return node.kind.displayName
    }

    private var backgroundColor: Color {
        if focus.selectedNodeID == node.id {
            return TenXPalette.color(TenXPalette.hoverNeutralHex)
        }
        return TenXPalette.color(TenXPalette.canvasHex)
    }

    private var borderColor: Color {
        if node.status == .failed { return TenXPalette.color(TenXPalette.signalRedHex) }
        if isHighlighted || focus.selectedNodeID == node.id {
            return TenXPalette.color(TenXPalette.interactiveCyanHex)
        }
        if changeKind != nil { return TenXPalette.color(TenXPalette.yellowHex) }
        return TenXPalette.color(TenXPalette.separatorHex)
    }

    @ViewBuilder private var border: some View {
        let shape = Rectangle()
        if node.status == .exists {
            shape.stroke(
                borderColor.opacity(isDimmed ? 0.24 : 1),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.stroke(
                borderColor.opacity(isDimmed ? 0.24 : 1),
                lineWidth: isHighlighted ? 2 : 1)
        }
    }

    @ViewBuilder private var statusMark: some View {
        Group {
            switch node.status {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            case .active:
                Circle()
                    .fill(TenXPalette.color(TenXPalette.cyanHex))
                    .frame(width: 6, height: 6)
            case .proposed:
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            case .planned:
                Image(systemName: "list.bullet")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            default:
                Circle()
                    .stroke(TenXPalette.color(TenXPalette.mutedTextHex), lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
        }
        .opacity(isDimmed ? 0.3 : 1)
    }
}

enum SessionMapNodeChangeKind: Equatable {
    case added
    case changed
    case removed
}

private extension SessionMapNodeKind {
    var displayName: String {
        rawValue.capitalized
    }
}
