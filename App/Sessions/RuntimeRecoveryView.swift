import SwiftUI

struct RuntimeRecoveryView: View {
    let exitCode: Int32?
    let onRestart: () -> Void
    let onOpenLog: () -> Void
    let onDismiss: () -> Void
    var restartLabel = "Restart session"
    var failureDescription: String? = nil
    var canRestart = true
    var onReviewPrompt: (() -> Void)? = nil
    var isIntentionalStop = false
    var isStopping = false
    var titleOverride: String? = nil

    var body: some View {
        CornerCard(color: TenXPalette.color(
            isIntentionalStop ? TenXPalette.mutedTextHex : TenXPalette.signalRedHex)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                Text(failureDescription ?? exitDescription)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                HStack(spacing: 4) {
                    if canRestart || isStopping {
                        Button(isStopping ? "Stopping…" : restartLabel, action: onRestart)
                            .buttonStyle(GhostActionStyle())
                            .disabled(isStopping)
                    }
                    if let onReviewPrompt {
                        Button("Review prompt", action: onReviewPrompt)
                            .buttonStyle(GhostActionStyle())
                    }
                    if !isIntentionalStop {
                        Button("Open log", action: onOpenLog)
                            .buttonStyle(GhostActionStyle(
                                color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    }
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(GhostActionStyle(
                            color: TenXPalette.color(TenXPalette.nearBlackHex)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        if let titleOverride { return titleOverride }
        if isIntentionalStop { return "Response stopped" }
        return failureDescription == nil ? "Session process stopped" : "Session needs attention"
    }

    private var exitDescription: String {
        if isIntentionalStop {
            return isStopping
                ? "Closing the session. Your transcript and staged input are preserved."
                : "Your transcript and staged input are preserved."
        }
        guard let exitCode else { return "OMP exited before reporting a status code." }
        return "OMP exited with status \(exitCode). Your transcript and draft are preserved."
    }
}
