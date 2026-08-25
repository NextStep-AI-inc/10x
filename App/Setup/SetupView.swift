import AppKit
import SwiftUI

struct SetupView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            BrandWordmark(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text("OMP required")
                    .font(TenXTypography.title(size: 38))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text("10x needs the OMP executable to start and resume agent sessions.")
                    .font(TenXTypography.body(size: 14))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            CornerCard(color: TenXPalette.color(TenXPalette.cyanHex)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Checked automatically")
                        .font(TenXTypography.body(weight: .semibold))
                    ForEach(OmpExecutableLocator.knownPaths, id: \.self) { path in
                        Text(path)
                            .font(TenXTypography.mono())
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
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
