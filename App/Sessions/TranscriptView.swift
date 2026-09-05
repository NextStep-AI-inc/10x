import SwiftUI

enum TranscriptScrollIntent: Equatable {
    case automatic
    case explicit
}

struct TranscriptView: View {
    static let contentMaxWidth: CGFloat = 860

    let controller: SessionController
    @State private var disclosureState = ToolDisclosureState()
    @State private var isUserScrolling = false
    @State private var searchResolution: TranscriptSearchResolution?
    @State private var consumedSearchNonce: UUID?
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled

    var body: some View {
        @Bindable var viewport = controller.viewport
        let allPresentationRows = Self.followObservation(for: controller.items)
        let presentationRows = TranscriptPresentationRow.visibleRows(
            from: allPresentationRows,
            isGroupExpanded: disclosureState.isGroupExpanded)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                LazyVStack(spacing: 22) {
                    if controller.runtimeState == .loading, controller.items.isEmpty,
                       controller.pendingSubmissions.isEmpty {
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
                    ForEach(presentationRows, id: \.id) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            if searchResolution?.rowID == row.id, let request = controller.transcriptSearchRequest,
                               let excerpt = searchResolution?.excerpt {
                                TranscriptPlainTextView(text: excerpt,
                                    font: TenXTypography.body(size: 12),
                                    color: TenXPalette.color(TenXPalette.nearBlackHex),
                                    highlightedQuery: request.query)
                                    .padding(8)
                                    .background(TenXPalette.color(TenXPalette.yellowHex).opacity(0.12))
                                    .accessibilityLabel("Search match: " + excerpt)
                            }
                            rowView(row)
                        }
                            .background(searchResolution?.rowID == row.id
                                ? TenXPalette.color(TenXPalette.yellowHex).opacity(0.05) : .clear)
                            .padding(.top, row.isGroupedTool ? -12 : 0)
                            .id(row.id)
                    }
                    ForEach(controller.pendingSubmissions) { submission in
                        VStack(alignment: .trailing, spacing: 5) {
                            MessageBubbleView(message: submission.message)
                            Text(submission.state.label)
                                .font(TenXTypography.body(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                        .id(submission.id)
                    }
                    if isAwaitingOutput {
                        TurnActivityView(startedAt: controller.turnStartedAt)
                            .id(TurnActivityView.transcriptID)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: Self.contentMaxWidth)
                .padding(.horizontal, 42)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                Color.clear.frame(height: 1).id(Self.bottomID)
                }
            }
            .environment(\.toolDisclosureState, disclosureState)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $viewport.anchorID, anchor: .top)
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(viewport.isFollowingLatest ? .bottom : nil, for: .sizeChanges)
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onScrollGeometryChange(for: TranscriptViewportGeometry.self) { geometry in
                TranscriptViewportGeometry(offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height, containerSize: geometry.containerSize)
            } action: { previous, current in
                viewport.observe(from: previous, to: current, isUserScrolling: isUserScrolling)
                if viewport.isFollowingLatest, current.hasResized(from: previous) {
                    scroll(proxy, to: Self.bottomID, intent: .automatic)
                }
            }
            .onChange(of: allPresentationRows) { _, _ in
                focusSearchResult(proxy, rows: allPresentationRows)
                guard viewport.isFollowingLatest else { return }
                scroll(proxy, to: Self.bottomID, intent: .automatic)
            }
            .task(id: controller.transcriptSearchRequest?.nonce) {
                searchResolution = nil
                focusSearchResult(proxy, rows: allPresentationRows)
            }
            // The indicator is not an item, so its arrival needs its own follow
            // or it appears below the fold on the send that created it.
            .onChange(of: isAwaitingOutput) { _, isAwaiting in
                guard isAwaiting, viewport.isFollowingLatest else { return }
                scroll(proxy, to: Self.bottomID, intent: .automatic)
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
        if !controller.viewport.isFollowingLatest, lastID != nil {
            Button {
                controller.focusSearchResult(nil)
                searchResolution = nil
                controller.viewport.isFollowingLatest = true
                scroll(
                    proxy,
                    to: Self.bottomID,
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

    private func focusSearchResult(_ proxy: ScrollViewProxy, rows: [TranscriptPresentationRow]) {
        guard let request = controller.transcriptSearchRequest,
              request.nonce != consumedSearchNonce,
              let resolution = TranscriptSearchResolver.resolve(request, in: rows) else { return }
        consumedSearchNonce = request.nonce
        searchResolution = resolution
        controller.viewport.isFollowingLatest = false
        if let groupID = resolution.groupID { disclosureState.setGroupExpanded(true, id: groupID) }
        disclosureState.setExpanded(true, id: request.entryID)
        Task { @MainActor in
            await Task.yield()
            guard controller.transcriptSearchRequest?.nonce == request.nonce else { return }
            controller.viewport.anchorID = resolution.rowID
            proxy.scrollTo(resolution.rowID, anchor: .center)
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
        if controller.pendingSubmissions.contains(where: { $0.state == .starting }) { return true }
        return TurnActivityView.isAwaitingOutput(
            runtimeState: controller.runtimeState,
            lastItem: controller.items.last)
    }

    private static let bottomID = "transcript-bottom"

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
            MessageBubbleView(message: message, highlightedQuery:
                searchResolution?.messageID == message.id ? controller.transcriptSearchRequest?.query : nil)
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
            if state.isQuestionInput {
                ExtensionQuestionCardView(state: state) { response in
                    await controller.respond(to: state, with: response)
                }
            } else {
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
