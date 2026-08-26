import SwiftUI

struct TranscriptView: View {
    let controller: SessionController
    @State private var disclosureState = ToolDisclosureState()
    @State private var isNearBottom = true
    @State private var hasPositionedInitialContent = false
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    if controller.runtimeState == .loading, controller.items.isEmpty {
                        loadingSkeleton
                    }
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
            .onScrollGeometryChange(for: Bool.self) { geometry in
                Self.shouldFollowBottom(
                    contentOffset: geometry.contentOffset.y,
                    containerHeight: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height)
            } action: { _, value in
                isNearBottom = value
            }
            .onChange(of: controller.items.last) { _, item in
                guard let item else { return }
                let shouldFollow = !hasPositionedInitialContent || isNearBottom
                hasPositionedInitialContent = true
                guard shouldFollow else { return }
                if isReduceMotionEnabled {
                    proxy.scrollTo(item.id, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(item.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    nonisolated static func shouldFollowBottom(
        contentOffset: CGFloat,
        containerHeight: CGFloat,
        contentHeight: CGFloat,
        threshold: CGFloat = 80
    ) -> Bool {
        contentHeight <= containerHeight
            || contentOffset + containerHeight >= contentHeight - threshold
    }

    private var activityIDs: [String] {
        controller.items.compactMap { item in
            switch item {
            case .tool, .subagent: item.id
            default: nil
            }
        }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([180.0, 320.0, 240.0], id: \.self) { width in
                Rectangle()
                    .frame(width: width, height: 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(TenXPalette.color(TenXPalette.separatorHex))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading session history")
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(threadStartAccessibilityLabel(date))
        case .message(let message):
            MessageBubbleView(message: message)
        case .annotation(let annotation):
            HStack(spacing: 8) {
                Text(annotation.title)
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                    .foregroundStyle(annotationColor(annotation.tone))
                if let detail = annotation.detail {
                    Text(detail)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                Spacer()
                if let timestamp = annotation.timestamp {
                    Text(timestamp.formatted(date: .omitted, time: .shortened))
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
            }
            .accessibilityElement(children: .combine)
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
            .accessibilityElement(children: .combine)
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
        }
    }

    private func threadStartAccessibilityLabel(_ date: Date?) -> String {
        guard let date else { return "Thread started" }
        return "Thread started \(date.formatted(date: .complete, time: .shortened))"
    }

    private func annotationColor(_ tone: TranscriptAnnotation.Tone) -> Color {
        switch tone {
        case .neutral:
            TenXPalette.color(TenXPalette.mutedTextHex)
        case .interactive:
            TenXPalette.color(TenXPalette.cyanHex)
        case .warning:
            TenXPalette.color(TenXPalette.yellowHex)
        case .error:
            TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}
