import SwiftUI

struct ActiveSessionView: View {
    let controller: SessionController

    var body: some View {
        VStack(spacing: 0) {
            SessionHeaderView(controller: controller)

            TranscriptView(items: controller.items)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ComposerView(
                draft: Bindable(controller).draft,
                presentation: .active(controller: controller),
                onSend: {
                    Task { await controller.sendPrompt() }
                })
            .frame(maxWidth: 780)
            .padding(.horizontal, 42)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
