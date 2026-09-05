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
        lastItem: TranscriptItem?
    ) -> Bool {
        guard runtimeState == .streaming else { return false }
        switch lastItem {
        case .message(let message):
            // Only a live assistant message is output in progress. A user
            // message is the thing being answered, so the run is still silent.
            return message.role != .assistant || message.isFinal || message.document.blocks.isEmpty
        case .tool(let presentation):
            return presentation.phase == .complete || presentation.phase == .failed
        case .subagent(let presentation):
            return !presentation.status.isActive
        case .extensionUI:
            // The approval card is waiting on the user, not on omp.
            return false
        default:
            return true
        }
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
