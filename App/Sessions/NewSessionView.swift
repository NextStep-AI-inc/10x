import AppKit
import SwiftUI

struct NewSessionView: View {
    let model: AppModel

    @State private var draft = ""
    @State private var flyout: ComposerFlyout?

    var body: some View {
        ZStack {
            if flyout != nil {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { flyout = nil }
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                ComposerView(
                    draft: $draft,
                    flyout: $flyout,
                    presentation: .newSession(
                        projectURL: model.selectedProjectURL,
                        projectURLs: ProjectSessionGrouper.choosableProjectURLs(
                            from: model.sessions,
                            including: model.selectedProjectURL,
                            knownProjectURLs: model.knownProjectURLs),
                        onChooseProject: model.chooseProject,
                        onAddExistingFolder: addExistingFolder),
                    controls: model.composerControls,
                    controlsMode: .newSession,
                    onSend: {
                        flyout = nil
                        model.startNewSession(prompt: draft)
                    })
                .frame(maxWidth: 780)
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
        }
        .onExitCommand {
            flyout = nil
        }
    }

    private func addExistingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseProject(url)
    }
}
