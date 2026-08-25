import SwiftUI

struct ApprovalCardView: View {
    let state: ExtensionUIState
    let onRespond: (ExtensionUIResponse) -> Void
    let onOpenURL: (URL) -> Void
    let onCopyURL: (URL) -> Void

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.nearBlackHex)) {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Button("Cancel") { onRespond(.confirmed(false)) }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
            }
        case .select(_, let title, let options, _):
            Text(title)
                .font(TenXTypography.body(size: 12, weight: .semibold))
            ForEach(options, id: \.label) { option in
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
            }
            Button("Cancel") { onRespond(.cancelled(timedOut: false)) }
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(TenXPalette.nearBlackHex)))
        case .openURL(_, let target, let instructions):
            titleAndMessage(
                title: "Continue in browser",
                message: instructions ?? target.absoluteString)
            HStack(spacing: 4) {
                Button("Open link") { onOpenURL(target) }
                    .buttonStyle(GhostActionStyle())
                Button("Copy link") { onCopyURL(target) }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
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
