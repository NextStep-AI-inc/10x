import SwiftUI

struct ComposerView: View {
    @Binding var draft: String
    let projectURL: URL?
    let onChooseProject: () -> Void
    let onSend: () -> Void

    private var canSend: Bool {
        projectURL != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .font(TenXTypography.body(size: 14))
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(minHeight: 112)
                .accessibilityLabel("Session prompt")

            HStack(spacing: 4) {
                Button(action: onChooseProject) {
                    Label(projectURL?.lastPathComponent ?? "Choose project", systemImage: "folder")
                }
                .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))

                Button("Local") {}
                    .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
                Button("GPT-5.6") {}
                    .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))
                Button("High") {}
                    .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.nearBlackHex)))

                Spacer()

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(canSend
                            ? TenXPalette.color(TenXPalette.nearBlackHex)
                            : TenXPalette.color(TenXPalette.separatorHex))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Start session")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(.white)
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
    }
}
