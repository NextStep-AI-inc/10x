import SwiftUI

struct TranscriptView: View {
    let controller: SessionController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    ForEach(controller.items) { item in
                        itemView(item)
                            .id(item.id)
                    }
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, 42)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.items.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: TranscriptItem) -> some View {
        switch item {
        case .message(_, let message, _):
            MessageBubbleView(message: message)
        case .notice(_, let level, let message):
            HStack(spacing: 8) {
                Text(level.capitalized)
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                Text(message)
                    .font(TenXTypography.body(size: 12))
                Spacer()
            }
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        case .tool(let presentation):
            switch ToolCardRegistry.kind(for: presentation.name) {
            case .read:
                ReadToolCardView(presentation: presentation)
            case .bash:
                BashToolCardView(presentation: presentation)
            case .edit:
                EditToolCardView(presentation: presentation)
            case .write:
                WriteToolCardView(presentation: presentation)
            case .search:
                SearchToolCardView(presentation: presentation)
            case .task:
                TaskToolCardView(presentation: presentation)
            case .todo:
                TodoToolCardView(presentation: presentation)
            case .web:
                WebToolCardView(presentation: presentation)
            case .generic:
                GenericToolCardView(presentation: presentation)
            }
        case .extensionUI(let state):
            ApprovalCardView(
                state: state,
                onRespond: { response in
                    Task { await controller.respond(to: state, with: response) }
                },
                onOpenURL: { url in
                    controller.openURL(url, requestID: state.id)
                },
                onCopyURL: { url in
                    controller.copyURL(url, requestID: state.id)
                })
        case .rawEvent:
            EmptyView()
        }
    }
}
