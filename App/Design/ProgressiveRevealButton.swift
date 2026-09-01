import SwiftUI

struct ProgressiveRevealButton: View {
    @Binding var reveal: ProgressiveReveal
    let total: Int
    let noun: String
    let accessibilityNoun: String

    var body: some View {
        if reveal.canRevealMore(total: total) {
            Button("Show \(reveal.nextPageCount(total: total)) more \(noun)") {
                reveal.revealNextPage(total: total)
            }
            .accessibilityLabel("Show \(reveal.nextPageCount(total: total)) more \(accessibilityNoun)")
            .buttonStyle(GhostActionStyle(horizontalPadding: 0))
        } else if reveal.visibleCount(total: total) > reveal.initialLimit {
            Button("Show fewer") {
                reveal.collapse()
            }
            .accessibilityLabel("Show fewer \(accessibilityNoun)")
            .buttonStyle(GhostActionStyle(horizontalPadding: 0))
        }
    }
}
