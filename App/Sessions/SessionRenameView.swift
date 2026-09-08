import SwiftUI

struct SessionRenameView: View {
    let request: SessionRenameRequest
    let isSaving: Bool
    let onDraftChange: (String) -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            TenXPalette.color(TenXPalette.canvasHex).opacity(0.82)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSaving { onCancel() }
                }

            CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Rename session")
                        .font(TenXTypography.accent(size: 20))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Session name")
                            .font(TenXTypography.mono(size: 10, weight: .semibold))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        TextField("Session name", text: draftBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(TenXTypography.body(size: 13))
                            .focused($isNameFocused)
                            .disabled(isSaving)
                            .onSubmit {
                                if !isSaving { onSave() }
                            }
                        if let errorMessage = request.errorMessage {
                            Text(errorMessage)
                                .font(TenXTypography.body(size: 12))
                                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                                .accessibilityLabel("Rename error: \(errorMessage)")
                        }
                    }

                    HStack(spacing: 10) {
                        Spacer()
                        Button("Cancel", action: onCancel)
                            .buttonStyle(GhostActionStyle())
                            .keyboardShortcut(.cancelAction)
                            .disabled(isSaving)
                        Button("Rename", action: onSave)
                            .buttonStyle(.borderedProminent)
                            .tint(TenXPalette.color(TenXPalette.cyanHex))
                            .disabled(isSaving)
                    }
                }
            }
            .frame(width: 420)
            .background(TenXPalette.surfaceElevated)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rename session")
        .accessibilityAddTraits(.isModal)
        .onExitCommand {
            if !isSaving { onCancel() }
        }
        .task {
            await Task.yield()
            isNameFocused = true
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { request.draft },
            set: onDraftChange)
    }
}
