import SwiftUI

struct FlyerStackView: View {
    let flyers: [Flyer]
    let onAction: (Flyer.Key, String) -> Void
    let onDismiss: (Flyer.Key) -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(flyers.suffix(3)), id: \.key) { flyer in
                FlyerRowView(
                    flyer: flyer,
                    onAction: { onAction(flyer.key, $0) },
                    onDismiss: { onDismiss(flyer.key) })
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
        } action: { height in
            onHeightChange(height)
        }
    }
}
