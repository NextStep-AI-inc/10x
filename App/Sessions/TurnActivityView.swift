import SwiftUI

/// Fills the silent stretches of a run: after a prompt is dispatched, and
/// between one piece of output finishing and the next starting.
///
/// Tool cards and a streaming message already report their own progress, so
/// this only appears when nothing else in the transcript is moving. Without it
/// a long first token reads as a hang.
struct TurnActivityView: View {
    let startedAt: Date?

    static let transcriptID = "turn-activity"

    /// True only while the run has produced nothing that is still moving.
    nonisolated static func isAwaitingOutput(
        runtimeState: SessionRuntimeState,
        items: [TranscriptItem]
    ) -> Bool {
        guard runtimeState == .streaming else { return false }
        let finalSection = TranscriptTurnProjection.sections(
            from: items, runtimeState: runtimeState).last
        let activeItems = finalSection?.state == nil ? items : finalSection?.items ?? []
        guard !activeItems.contains(where: requiresUserInput) else { return false }
        guard !activeItems.contains(where: hasOngoingNonMessageActivity) else { return false }

        // Packed messages can leave assistant text nonfinal before a completed
        // tool. Only the latest response item says whether that text is moving.
        for item in activeItems.reversed() {
            switch item {
            case .message(let message) where message.role == .assistant:
                return message.isFinal || message.document.blocks.isEmpty
            case .tool, .subagent:
                return true
            default:
                continue
            }
        }
        return true
    }

    private nonisolated static func hasOngoingNonMessageActivity(_ item: TranscriptItem) -> Bool {
        switch item {
        case .tool(let presentation):
            return presentation.phase == .running
        case .subagent(let presentation):
            return presentation.status.isActive
        case .message, .threadStart, .annotation, .notice, .extensionUI:
            return false
        }
    }

    private nonisolated static func requiresUserInput(_ item: TranscriptItem) -> Bool {
        guard case .extensionUI(let state) = item else { return false }
        return state.requiresUserInput
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Working…")
                .font(TenXTypography.body(size: 11, weight: .semibold))
            if let startedAt {
                Text(startedAt, style: .timer)
                    .font(TenXTypography.mono(size: 10))
                    .monospacedDigit()
            }
            Spacer()
        }
        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working")
    }
}
