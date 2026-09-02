import SwiftUI

enum TranscriptScrollIntent: Equatable {
    case automatic
    case explicit
}

struct TranscriptView: View {
    static let contentMaxWidth: CGFloat = 860

    let controller: SessionController
    @State private var disclosureState = ToolDisclosureState()
    @State private var isNearBottom = true
    @State private var hasPositionedInitialContent = false
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @Environment(ToolDetailPreferenceStore.self) private var detailPreference:
        ToolDetailPreferenceStore?

    var body: some View {
        let allPresentationRows = Self.followObservation(for: controller.items)
        let presentationRows = TranscriptPresentationRow.visibleRows(
            from: allPresentationRows,
            isGroupExpanded: disclosureState.isGroupExpanded)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    if controller.runtimeState == .loading, controller.items.isEmpty {
                        loadingSkeleton
                    }
                    HStack(spacing: 4) {
                        Spacer()
                        ToolDetailModeControl(mode: disclosureState.mode, onSelect: select)
                    }
                    ForEach(presentationRows, id: \.id) { row in
                        rowView(row)
                            .padding(.top, row.isGroupedTool ? -12 : 0)
                            .id(row.id)
                    }
                    if isAwaitingOutput {
                        TurnActivityView(startedAt: controller.turnStartedAt)
                            .id(TurnActivityView.transcriptID)
                    }
                }
                .frame(maxWidth: Self.contentMaxWidth)
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
            .onChange(of: allPresentationRows) { _, _ in
                guard let lastID = presentationRows.last?.id else { return }
                let shouldFollow = !hasPositionedInitialContent || isNearBottom
                hasPositionedInitialContent = true
                guard shouldFollow else { return }
                scroll(proxy, to: lastID, intent: .automatic)
            }
            // The indicator is not an item, so its arrival needs its own follow
            // or it appears below the fold on the send that created it.
            .onChange(of: isAwaitingOutput) { _, isAwaiting in
                guard isAwaiting, isNearBottom else { return }
                scroll(proxy, to: TurnActivityView.transcriptID, intent: .automatic)
            }
            // Picks up the stored mode on open, and any change made from
            // another window while this transcript is on screen. Unanimated on
            // purpose: `initial: true` fires on open, and animating there would
            // play every card opening as the transcript appears. Only an
            // explicit selection animates, in `select(_:)`.
            .onChange(of: detailPreference?.mode ?? .auto, initial: true) { _, mode in
                disclosureState.setMode(mode)
            }
            .overlay(alignment: .bottom) {
                scrollToBottomButton(proxy, lastID: presentationRows.last?.id)
            }
        }
    }

    /// Only offered once following has actually been broken, so it never sits
    /// over a transcript that is already tracking the bottom.
    @ViewBuilder
    private func scrollToBottomButton(_ proxy: ScrollViewProxy, lastID: String?) -> some View {
        if hasPositionedInitialContent, !isNearBottom, let lastID {
            Button {
                scroll(
                    proxy,
                    to: isAwaitingOutput ? TurnActivityView.transcriptID : lastID,
                    intent: .explicit)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("Jump to latest")
                        .font(TenXTypography.body(size: 11, weight: .medium))
                }
                .foregroundStyle(TenXPalette.onEmphasis)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(TenXPalette.color(TenXPalette.nearBlackHex))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
            .transition(.opacity)
            .accessibilityLabel("Jump to latest")
        }
    }

    private func scroll(
        _ proxy: ScrollViewProxy,
        to id: String,
        intent: TranscriptScrollIntent
    ) {
        if Self.shouldAnimateScroll(
            intent: intent,
            isReduceMotionEnabled: isReduceMotionEnabled) {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    nonisolated static func shouldAnimateScroll(
        intent: TranscriptScrollIntent,
        isReduceMotionEnabled: Bool
    ) -> Bool {
        intent == .explicit && !isReduceMotionEnabled
    }

    private var isAwaitingOutput: Bool {
        TurnActivityView.isAwaitingOutput(
            runtimeState: controller.runtimeState,
            lastItem: controller.items.last)
    }

    nonisolated static func followObservation(
        for items: [TranscriptItem]
    ) -> [TranscriptPresentationRow] {
        TranscriptPresentationRow.rows(from: items)
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

    private func select(_ mode: ToolDetailMode) {
        detailPreference?.select(mode)
        let update = { disclosureState.setMode(mode) }
        if isReduceMotionEnabled { update() }
        else { withAnimation(.easeInOut(duration: 0.14), update) }
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Three grey hairlines alone read as an empty transcript, so the
            // opening step says so in words.
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Opening session…")
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            ForEach([180.0, 320.0, 240.0], id: \.self) { width in
                Rectangle()
                    .frame(width: width, height: 2)
                    .foregroundStyle(TenXPalette.color(TenXPalette.separatorHex))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening session")
    }

    @ViewBuilder
    private func rowView(_ row: TranscriptPresentationRow) -> some View {
        switch row {
        case .item(let item):
            itemView(item)
        case .toolGroup(let group):
            ToolCallGroupView(group: group)
        case .groupedTool(_, let tool):
            ToolCardView(presentation: tool)
                .equatable()
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
                .equatable()
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
            ToolCardView(presentation: presentation)
                .equatable()
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
