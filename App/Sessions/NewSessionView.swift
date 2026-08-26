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
                    onChooseProject: model.chooseNewProject),
                onSend: {
                    model.startNewSession(prompt: draft)
                })
            .frame(maxWidth: 780)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 42)
        .padding(.bottom, 28)
    }
}
