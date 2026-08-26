import SwiftUI

struct AssistantMessageContentView: View, Equatable {
    let message: TranscriptMessage

    nonisolated static func == (lhs: AssistantMessageContentView, rhs: AssistantMessageContentView) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.document == rhs.message.document
            && lhs.message.isFinal == rhs.message.isFinal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MessageBubbleView.assistantContentSpacing) {
            ForEach(Array(message.document.blocks.enumerated()), id: \.offset) { _, block in
                MessageBlockView(block: block)
            }
            let references = TranscriptReference.extract(from: message.visibleText)
            if !references.isEmpty {
                FlowLayout(spacing: 2) {
                    ForEach(references, id: \.self) { reference in
                        TranscriptReferenceView(reference: reference)
                    }
                }
            }
        }
    }
}
