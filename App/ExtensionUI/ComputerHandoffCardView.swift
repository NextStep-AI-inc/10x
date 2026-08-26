import SwiftUI

struct ComputerHandoffCardView: View {
    let target: String
    let reason: String
    let onApprove: () -> Void
    let onCancel: () -> Void
    @FocusState private var focusedAction: HandoffFocus?

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.nearBlackHex)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Foreground access required")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                Text(message)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    Button("Open Agent Desktop and Continue", action: onApprove)
                        .buttonStyle(GhostActionStyle())
                        .keyboardShortcut(.defaultAction)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($focusedAction, equals: .approve)
                        .accessibilityLabel("Open Agent Desktop and continue foreground access")
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GhostActionStyle(
                            color: TenXPalette.color(TenXPalette.nearBlackHex)))
                        .keyboardShortcut(.cancelAction)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($focusedAction, equals: .cancel)
                        .accessibilityLabel("Cancel foreground access")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await Task.yield()
            focusedAction = .approve
        }
    }

    private var message: String {
        let trimmedReason = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let normalizedReason = trimmedReason.prefix(1).lowercased() + trimmedReason.dropFirst()
        return "\(target) needs foreground access because \(normalizedReason)."
    }
}

private enum HandoffFocus: Hashable {
    case approve
    case cancel
}
