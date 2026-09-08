import SwiftUI

/// Drawn inside a click-through panel exactly over the claimed window.
struct ComputerUseOverlayView: View {
    let state: OverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            TwoCornerFrame()
                .stroke(TenXPalette.color(TenXPalette.cyanHex), lineWidth: 1.5)

            tag
                .offset(x: -1, y: -22)

            if let cursor = state.cursor {
                CursorDot(kind: state.cursorKind)
                    .position(cursor)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.cursor)
    }

    private var tag: some View {
        HStack(spacing: 6) {
            Text(state.app)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
            if let status = state.status, !status.isEmpty {
                Text(status)
                    .font(TenXTypography.mono(size: 9))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(TenXPalette.color(TenXPalette.canvasHex))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(TenXPalette.color(TenXPalette.nearBlackHex))
    }
}

/// Two opposite corners of a rectangle — the 10x frame language.
struct TwoCornerFrame: Shape {
    var cornerLength: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        // bottom-right
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        return path
    }
}

struct CursorDot: View {
    let kind: String?

    var body: some View {
        Circle()
            .fill(TenXPalette.color(TenXPalette.cyanHex))
            .frame(width: 10, height: 10)
            .overlay {
                Circle().stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 2)
            .accessibilityLabel("Agent cursor\(kind.map { ": \($0)" } ?? "")")
    }
}
