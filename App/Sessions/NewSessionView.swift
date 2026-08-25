import AppKit
import SwiftUI

struct NewSessionView: View {
    let model: AppModel

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 8) {
                Text("What should we build?")
                    .font(TenXTypography.title(size: 38))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text("Choose a project and give 10x a clear outcome.")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            ComposerView(
                draft: $draft,
                projectURL: model.selectedProjectURL,
                onChooseProject: chooseProject,
                onSend: {})
            .frame(maxWidth: 680)

            Spacer()
                .frame(maxHeight: 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(42)
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseProject(url)
    }
}
