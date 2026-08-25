import SwiftUI

struct RuntimeRecoveryView: View {
    let exitCode: Int32?
    let onRestart: () -> Void
    let onOpenLog: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.signalRedHex)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Session process stopped")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                Text(exitDescription)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                HStack(spacing: 4) {
                    Button("Restart session", action: onRestart)
                        .buttonStyle(GhostActionStyle())
                    Button("Open log", action: onOpenLog)
                        .buttonStyle(GhostActionStyle(
                            color: TenXPalette.color(TenXPalette.nearBlackHex)))
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(GhostActionStyle(
                            color: TenXPalette.color(TenXPalette.nearBlackHex)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var exitDescription: String {
        guard let exitCode else { return "OMP exited before reporting a status code." }
        return "OMP exited with status \(exitCode). Your transcript and draft are preserved."
    }
}
