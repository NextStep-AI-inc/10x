import SwiftUI

/// Drawn inside a click-through panel exactly over the claimed window.
/// The panel is the window frame plus `sideInset` on every side plus
/// `tagHeadroom` above — the tag lives in that headroom, the frame and
/// cursor are offset down/into the window's rect within the panel.
struct ComputerUseOverlayView: View {
    static let tagHeadroom: CGFloat = 24
    static let sideInset: CGFloat = 6

    let state: OverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            TwoCornerFrame()
                .stroke(TenXPalette.color(TenXPalette.cyanHex), lineWidth: 1.5)
                .padding(EdgeInsets(
                    top: Self.tagHeadroom, leading: Self.sideInset,
                    bottom: Self.sideInset, trailing: Self.sideInset))

            tag
                .padding(.top, 3)
                .padding(.leading, Self.sideInset - 1)

            if let cursor = state.cursor {
                CursorDot(kind: state.cursorKind)
                    .position(x: cursor.x + Self.sideInset, y: cursor.y + Self.tagHeadroom)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.cursor)
    }

    private var tag: some View {
        HStack(spacing: 6) {
            Text(state.identity)
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
