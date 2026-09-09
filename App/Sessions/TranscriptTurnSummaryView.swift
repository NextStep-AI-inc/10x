import SwiftUI

struct TranscriptTurnSummaryView: View {
    let state: TranscriptTurnState
    let duration: TimeInterval?
    let files: [TranscriptTurnFile]
    let onSelectFile: (TranscriptTurnFile) -> Void

    init(
        state: TranscriptTurnState,
        duration: TimeInterval?,
        files: [TranscriptTurnFile] = [],
        onSelectFile: @escaping (TranscriptTurnFile) -> Void = { _ in }
    ) {
        self.state = state
        self.duration = duration
        self.files = files
        self.onSelectFile = onSelectFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.label(state: state, duration: duration))
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Self.accessibilityLabel(state: state, duration: duration))

            if !files.isEmpty {
                TranscriptTurnFilesView(files: files, onSelect: onSelectFile)
            }
        }
    }

    nonisolated static func label(
        state: TranscriptTurnState,
        duration: TimeInterval?
    ) -> String {
        let status = switch state {
        case .completed: "Completed"
        case .stopped, .interrupted: "Stopped"
        case .failed: "Failed"
        case .working, .pendingInput, .unknown: ""
        }
        guard state == .completed, let duration else { return status }
        return "\(status) · \(String(format: "%.1fs", duration))"
    }

    nonisolated static func accessibilityLabel(
        state: TranscriptTurnState,
        duration: TimeInterval?
    ) -> String {
        Self.label(state: state, duration: duration)
            .replacingOccurrences(of: " · ", with: ", ")
    }

    private var color: Color {
        switch state {
        case .failed:
            TenXPalette.color(TenXPalette.signalRedHex)
        case .completed, .stopped, .interrupted, .working, .pendingInput, .unknown:
            TenXPalette.color(TenXPalette.mutedTextHex)
        }
    }
}
