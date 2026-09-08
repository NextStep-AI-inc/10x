import SwiftUI

struct WorkingProgressIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(index == 1
                        ? TenXPalette.color(TenXPalette.cyanHex)
                        : TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(width: 2, height: 8)
                    .scaleEffect(
                        x: 1,
                        y: reduceMotion ? 0.55 : scale(for: index),
                        anchor: .bottom)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.64)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12),
                        value: isAnimating)
            }
        }
        .frame(width: 12, height: 8, alignment: .bottom)
        .onAppear { isAnimating = !reduceMotion }
        .onChange(of: reduceMotion) { _, reduceMotion in
            isAnimating = !reduceMotion
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working")
    }

    private func scale(for index: Int) -> CGFloat {
        let resting: [CGFloat] = [0.45, 0.7, 0.55]
        let active: [CGFloat] = [0.9, 0.45, 1]
        return (isAnimating ? active : resting)[index]
    }
}
