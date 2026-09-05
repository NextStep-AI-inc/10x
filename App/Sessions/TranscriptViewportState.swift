import Observation
import SwiftUI

@MainActor
@Observable
final class TranscriptViewportState {
    var isFollowingLatest = true
    var anchorID: String?

    func observe(from previous: TranscriptViewportGeometry, to current: TranscriptViewportGeometry, isUserScrolling: Bool) {
        guard isUserScrolling else { return }
        if current.offset < previous.offset - 0.5 {
            isFollowingLatest = false
        } else if current.bottomDistance <= 2 {
            isFollowingLatest = true
        }
    }
}

struct TranscriptViewportGeometry: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let containerSize: CGSize

    var bottomDistance: CGFloat { max(0, contentHeight - offset - containerSize.height) }

    func hasResized(from previous: Self) -> Bool {
        contentHeight != previous.contentHeight || containerSize != previous.containerSize
    }
}
