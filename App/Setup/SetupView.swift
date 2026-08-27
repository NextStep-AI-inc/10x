import AppKit
import SwiftUI

struct SetupView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            BrandWordmark(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(TenXTypography.title(size: 38))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text(explanation)
                    .font(TenXTypography.body(size: 14))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
                VStack(alignment: .leading, spacing: 12) {
                    if let unrunnable = model.unrunnableOmpURL {
                        Text("Found at")
                            .font(TenXTypography.body(weight: .semibold))
                        Text(unrunnable.path)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                        Text("Run it in a terminal to see why it fails:")
                            .font(TenXTypography.body(size: 12))
                        Text("\(unrunnable.path) --version")
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                    } else {
                        Text("Checked automatically")
                            .font(TenXTypography.body(weight: .semibold))
                        ForEach(OmpExecutableLocator.knownPaths, id: \.self) { path in
                            Text(path)
                                .font(TenXTypography.mono())
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let setupError = model.setupError {
                Text(setupError)
                    .font(TenXTypography.mono())
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .textSelection(.enabled)
            }

            Button("Locate OMP") {
                locateOmp()
            }
            .buttonStyle(GhostActionStyle())
            .accessibilityHint("Choose the OMP executable on this Mac")
        }
        .frame(width: 470, alignment: .leading)
        .padding(56)
    }

    private var title: String {
        model.unrunnableOmpURL == nil ? "OMP required" : "OMP won’t run"
    }

    private var explanation: String {
        model.unrunnableOmpURL == nil
            ? "10x needs the OMP executable to start and resume agent sessions."
            : "10x found OMP but couldn’t run it. Its interpreter may be missing."
    }

    private func locateOmp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use OMP"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.useOmp(at: url) }
    }
}
