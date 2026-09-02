import SwiftUI

struct SessionDeletionConfirmationView: View {
    let request: SessionDeletionRequest
    let onCancel: () -> Void
    let onDelete: () -> Void

    @FocusState private var isCancelFocused: Bool
    @AccessibilityFocusState private var isCancelAccessibilityFocused: Bool

    var body: some View {
        ZStack {
            TenXPalette.color(TenXPalette.canvasHex).opacity(0.82)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            CornerCard(color: TenXPalette.color(TenXPalette.signalRedHex)) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.title)
                            .font(TenXTypography.accent(size: 20))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        Text(request.message)
                            .font(TenXTypography.body(size: 13))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Spacer()
                        Button("Cancel", action: onCancel)
                            .buttonStyle(GhostActionStyle())
                            .keyboardShortcut(.cancelAction)
                            .focused($isCancelFocused)
                            .accessibilityFocused($isCancelAccessibilityFocused)
                            .onKeyPress(.escape) {
                                onCancel()
                                return .handled
                            }
                        Button("Delete", action: onDelete)
                            .buttonStyle(.borderedProminent)
                            .tint(TenXPalette.color(TenXPalette.signalRedHex))
                    }
                }
            }
            .frame(width: 420)
            .background(TenXPalette.surfaceElevated)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title)
        .accessibilityAddTraits(.isModal)
        .onExitCommand(perform: onCancel)
        .task {
            await Task.yield()
            isCancelFocused = true
            isCancelAccessibilityFocused = true
        }
    }
}
