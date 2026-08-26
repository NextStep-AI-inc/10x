import SwiftUI

struct StartupLedgerView: View {
    let rows: [SplashLedgerRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 16) {
                    Text(row.title)
                    Spacer(minLength: 12)
                    Text(row.status.rawValue)
                        .foregroundStyle(statusColor(row.status))
                }
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .frame(height: 25)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(height: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
            }
        }
        .frame(width: 286)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Startup preparation")
    }

    private func statusColor(_ status: StartupStageStatus) -> Color {
        switch status {
        case .queued:
            TenXPalette.color(TenXPalette.mutedTextHex)
        case .loading:
            TenXPalette.color(TenXPalette.cyanHex)
        case .ready:
            TenXPalette.color(TenXPalette.nearBlackHex)
        case .stopped:
            TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}
