import SwiftUI

struct TranscriptView: View {
    let controller: SessionController
    @State private var disclosureState = ToolDisclosureState()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    if activityIDs.count >= 4 {
                        HStack(spacing: 4) {
                            Spacer()
                            Button("Collapse all") {
                                disclosureState.collapseAll(ids: activityIDs)
                            }
                            .buttonStyle(GhostActionStyle(
                                color: TenXPalette.color(TenXPalette.mutedTextHex)))
                            Button("Expand active") {
                                disclosureState.expand(ids: activeActivityIDs)
                            }
                            .buttonStyle(GhostActionStyle())
                        }
                    }
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
            .environment(\.toolDisclosureState, disclosureState)
            .scrollIndicators(.hidden)
            .onChange(of: controller.items.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var activityIDs: [String] {
        controller.items.compactMap { item in
            switch item {
            case .tool, .subagent: item.id
            default: nil
            }
        }
    }

    private var activeActivityIDs: [String] {
        controller.items.compactMap { item in
            switch item {
            case .tool(let presentation) where presentation.phase != .complete:
                presentation.id
            case .subagent(let presentation) where presentation.status.isActive
                || presentation.status.isError:
                presentation.id
            default:
                nil
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: TranscriptItem) -> some View {
        switch item {
        case .threadStart(_, let date):
            HStack(spacing: 8) {
                Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "Thread started")
                    .font(TenXTypography.mono(size: 10))
                Spacer()
            }
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        case .message(let message):
            MessageBubbleView(message: message)
        case .annotation(let annotation):
            HStack(spacing: 8) {
                Text(annotation.title)
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                if let detail = annotation.detail {
                    Text(detail)
                        .font(TenXTypography.mono(size: 10))
                }
                Spacer()
            }
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        case .subagent(let presentation):
            SubagentCardView(presentation: presentation)
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
