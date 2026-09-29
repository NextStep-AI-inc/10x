import SwiftUI

struct NewSessionView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if let message = model.newSessionRecoveryMessage {
                ComposerRecoveryNotice(message: message)
                    .frame(maxWidth: 780)
                    .padding(.bottom, 10)
            }

        }
        .padding(.horizontal, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
