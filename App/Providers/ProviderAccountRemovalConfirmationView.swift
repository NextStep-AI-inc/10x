import SwiftUI

struct ProviderAccountRemovalConfirmationPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let cancelActionLabel = "Cancel"
    let confirmActionLabel = "Remove account"

    init(
        providerName: String,
        accountLabel: String,
        affectedSessionCount: Int,
        isLastAccount: Bool
    ) {
        if isLastAccount {
            title = "Remove the last account?"
            message = "This disconnects \(providerName). Sessions using this provider cannot continue through it."
        } else {
            title = "Remove \(accountLabel)?"
            switch affectedSessionCount {
            case 0:
                message = "No 10x-managed sessions use this account."
            case 1:
                message = "1 10x-managed session uses this account. It moves to another account before removal. If it is generating, its current turn finishes first."
            default:
                message = "\(affectedSessionCount) 10x-managed sessions use this account. They move to another account before removal. Generating turns finish first."
            }
        }
    }
}

struct ProviderAccountRemovalConfirmationView: View {
    let providerName: String
    let accountLabel: String
    let affectedSessionCount: Int
    let isLastAccount: Bool
    let isRemoving: Bool
    let onCancel: () -> Void
    let onRemove: () -> Void

    @FocusState private var isCancelFocused: Bool
    @AccessibilityFocusState private var isCancelAccessibilityFocused: Bool

    var body: some View {
        ZStack {
            Color.white.opacity(0.82)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isRemoving else { return }
                    onCancel()
                }

            CornerCard(color: TenXPalette.color(TenXPalette.signalRedHex)) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(presentation.title)
                            .font(TenXTypography.accent(size: 20))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        Text(presentation.message)
                            .font(TenXTypography.body(size: 13))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Spacer()
                        Button(presentation.cancelActionLabel, action: onCancel)
                            .buttonStyle(GhostActionStyle())
                            .disabled(isRemoving)
                            .keyboardShortcut(.cancelAction)
                            .focused($isCancelFocused)
                            .accessibilityFocused($isCancelAccessibilityFocused)
                        Button(action: onRemove) {
                            if isRemoving {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Removing…")
                                }
                            } else {
                                Text(presentation.confirmActionLabel)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TenXPalette.color(TenXPalette.signalRedHex))
                        .disabled(isRemoving)
                    }
                }
            }
            .frame(width: 420)
            .background(Color.white)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.title)
        .accessibilityAddTraits(.isModal)
        .onExitCommand {
            guard !isRemoving else { return }
            onCancel()
        }
        .task {
            await Task.yield()
            isCancelFocused = true
            isCancelAccessibilityFocused = true
        }
    }

    private var presentation: ProviderAccountRemovalConfirmationPresentation {
        ProviderAccountRemovalConfirmationPresentation(
            providerName: providerName,
            accountLabel: accountLabel,
            affectedSessionCount: affectedSessionCount,
            isLastAccount: isLastAccount)
    }
}
