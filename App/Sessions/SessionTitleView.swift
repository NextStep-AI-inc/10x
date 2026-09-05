import SwiftUI

struct SessionTitleView: View {
    let title: String
    let isLoading: Bool
    @State private var isShimmering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isLoading {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(width: 130, height: 9)
                .overlay {
                    if !reduceMotion {
                        LinearGradient(colors: [.clear, TenXPalette.surfaceElevated, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 65)
                            .offset(x: isShimmering ? 130 : -130)
                            .animation(.linear(duration: 1.25).repeatForever(autoreverses: false), value: isShimmering)
                    }
                }
                .clipped()
                .onAppear { isShimmering = true }
                .accessibilityLabel("Naming session")
        } else {
            Text(title).lineLimit(1)
        }
    }
}

enum SessionActivityState: String {
    case working = "Working"
    case ready = "Ready"
    case needsInput = "Needs your response"
    case failed = "Failed"
    case stopped = "Stopped"

    var color: Color {
        switch self {
        case .working, .ready: TenXPalette.color(TenXPalette.cyanHex)
        case .needsInput: TenXPalette.color(TenXPalette.yellowHex)
        case .failed: TenXPalette.color(TenXPalette.signalRedHex)
        case .stopped: TenXPalette.color(TenXPalette.mutedTextHex)
        }
    }
}
