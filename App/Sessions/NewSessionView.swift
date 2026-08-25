import AppKit
import SwiftUI

struct NewSessionView: View {
    let model: AppModel

    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ComposerView(
                draft: $draft,
                presentation: .newSession(
                    projectURL: model.selectedProjectURL,
                    onChooseProject: chooseProject),
                onSend: {
                    model.startNewSession(prompt: draft)
                })
            .frame(maxWidth: 780)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 42)
        .padding(.bottom, 28)
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
