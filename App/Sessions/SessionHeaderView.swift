import SwiftUI

struct SessionHeaderView: View {
    let controller: SessionController

    var body: some View {
        ZStack {
            VStack(spacing: 3) {
                Text(controller.title)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !controller.headerMetadata.displayLine.isEmpty {
                    Text(controller.headerMetadata.displayLine)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 360)

            HStack(spacing: 8) {
                Spacer()
                Text(runtimeLabel)
                    .foregroundStyle(runtimeColor)
                    .accessibilityLabel("Session status")
                    .accessibilityValue(runtimeLabel)
                Text(controller.modelName)
                Text(controller.thinkingLevel)
                if let contextPercentage = controller.contextPercentage {
                    Text("\(contextPercentage)%")
                }
                if controller.runtimeState == .streaming {
                    Button("Stop") {
                        Task { await controller.abort() }
                    }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.signalRedHex)))
                }
            }
            .font(TenXTypography.body(size: 10, weight: .medium))
        }
        .frame(height: 54)
        .padding(.leading, 42)
        .padding(.trailing, 92)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)
        }
    }

    private var runtimeLabel: String {
        switch controller.runtimeState {
        case .loading: return "Loading"
        case .idle: return "Ready"
        case .streaming: return "Running"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }

    private var runtimeColor: Color {
        switch controller.runtimeState {
        case .streaming:
            return TenXPalette.color(TenXPalette.cyanHex)
        case .stopped, .failed:
            return TenXPalette.color(TenXPalette.signalRedHex)
        case .loading, .idle:
            return TenXPalette.color(TenXPalette.mutedTextHex)
        }
    }
}
