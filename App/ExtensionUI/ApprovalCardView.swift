import SwiftUI

struct ApprovalCardView: View {
    let state: ExtensionUIState
    let onRespond: (ExtensionUIResponse) -> Void
    let onOpenURL: (URL) -> Void
    let onCopyURL: (URL) -> Void
    @FocusState private var focusedAction: ApprovalFocus?

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.nearBlackHex)) {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await Task.yield()
            focusedAction = .primary
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .confirm(_, let title, let message, _):
            titleAndMessage(title: title, message: message)
            HStack(spacing: 4) {
                Button("Run") { onRespond(.confirmed(true)) }
                    .buttonStyle(GhostActionStyle())
                    .keyboardShortcut(.defaultAction)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focusedAction, equals: .primary)
                    .accessibilityLabel(ApprovalAccessibility.actionLabel(
                        name: "Run",
                        scope: "This request"))
                Button("Cancel") { onRespond(.confirmed(false)) }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    .keyboardShortcut(.cancelAction)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focusedAction, equals: .secondary)
                    .accessibilityLabel(ApprovalAccessibility.actionLabel(
                        name: "Cancel",
                        scope: "This request"))
            }
        case .select(_, let title, let options, _):
            Text(title)
                .font(TenXTypography.body(size: 12, weight: .semibold))
            ForEach(Array(options.enumerated()), id: \.element.label) { index, option in
                Button {
                    onRespond(.value(option.label))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                        if let detail = option.detail {
                            Text(detail)
                                .font(TenXTypography.body(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                    }
                }
                .buttonStyle(GhostActionStyle())
                .focusable()
                .focusEffectDisabled()
                .focused($focusedAction, equals: index == 0 ? .primary : .option(index))
                .accessibilityLabel(ApprovalAccessibility.actionLabel(
                    name: option.label,
                    scope: option.detail ?? "Select option"))
            }
            Button("Cancel") { onRespond(.cancelled(timedOut: false)) }
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(TenXPalette.nearBlackHex)))
                .keyboardShortcut(.cancelAction)
                .focusable()
                .focusEffectDisabled()
                .focused($focusedAction, equals: .secondary)
                .accessibilityLabel(ApprovalAccessibility.actionLabel(
                    name: "Cancel",
                    scope: "Selection"))
        case .openURL(_, let target, let instructions):
            titleAndMessage(
                title: "Continue in browser",
                message: instructions ?? target.absoluteString)
            HStack(spacing: 4) {
                Button("Open link") { onOpenURL(target) }
                    .buttonStyle(GhostActionStyle())
                    .keyboardShortcut(.defaultAction)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focusedAction, equals: .primary)
                    .accessibilityLabel(ApprovalAccessibility.actionLabel(
                        name: "Open link",
                        scope: target.host() ?? "Browser"))
                Button("Copy link") { onCopyURL(target) }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focusedAction, equals: .secondary)
                    .accessibilityLabel(ApprovalAccessibility.actionLabel(
                        name: "Copy link",
                        scope: target.host() ?? "Browser"))
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func titleAndMessage(title: String, message: String) -> some View {
        Text(title)
            .font(TenXTypography.body(size: 12, weight: .semibold))
        Text(message)
            .font(TenXTypography.body(size: 11))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .textSelection(.enabled)
    }
}

private enum ApprovalFocus: Hashable {
    case primary
    case secondary
    case option(Int)
}
