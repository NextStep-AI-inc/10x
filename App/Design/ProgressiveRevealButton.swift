import SwiftUI

struct ProgressiveRevealButton: View {
    @Binding var reveal: ProgressiveReveal
    let total: Int
    let noun: String
    let accessibilityNoun: String

    var body: some View {
        if reveal.canRevealMore(total: total) {
            let count = reveal.nextPageCount(total: total)
            Button(ProgressiveRevealCopy.label(count: count, noun: noun)) {
                reveal.revealNextPage(total: total)
            }
            .accessibilityLabel(ProgressiveRevealCopy.label(count: count, noun: accessibilityNoun))
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

enum ProgressiveRevealCopy {
    static func label(count: Int, noun: String) -> String {
        "Show \(count.formatted()) more \(count == 1 ? singular(noun) : noun)"
    }

    private static func singular(_ noun: String) -> String {
        let suffixes: [(plural: String, singular: String)] = [
            ("characters", "character"),
            ("entries", "entry"),
            ("items", "item"),
            ("lines", "line"),
            ("sessions", "session"),
        ]
        guard let suffix = suffixes.first(where: { noun.hasSuffix($0.plural) }) else {
            return noun
        }
        return String(noun.dropLast(suffix.plural.count)) + suffix.singular
    }
}
