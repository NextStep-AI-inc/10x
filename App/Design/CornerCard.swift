import SwiftUI

struct CornerCard<Content: View>: View {
    let color: Color
    let content: Content

    init(
        color: Color = TenXPalette.color(TenXPalette.nearBlackHex),
        @ViewBuilder content: () -> Content
    ) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .overlay {
                CornerFrameShape()
                    .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .square))
                    .allowsHitTesting(false)
            }
    }
}

private struct CornerFrameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(28, min(rect.width, rect.height) * 0.28)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))

        return path
    }
}
