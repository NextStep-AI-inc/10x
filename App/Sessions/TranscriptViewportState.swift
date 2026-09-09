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

    func observeVisibleTargets(
        _ visibleIDs: [String],
        orderedIDs: [String],
        isUserScrolling: Bool
    ) {
        guard isUserScrolling else { return }
        let visibleIDSet = Set(visibleIDs)
        guard let firstVisibleID = orderedIDs.first(where: visibleIDSet.contains),
              firstVisibleID != anchorID else { return }
        anchorID = firstVisibleID
    }

    nonisolated static func restorationTarget(
        anchorID: String?,
        isFollowingLatest: Bool,
        hasSearchRequest: Bool,
        visibleIDs: Set<String>,
        hiddenTargetGroupID: String?
    ) -> String? {
        guard !isFollowingLatest, !hasSearchRequest, let anchorID else { return nil }
        if visibleIDs.contains(anchorID) { return anchorID }
        guard let hiddenTargetGroupID, visibleIDs.contains(hiddenTargetGroupID) else { return nil }
        return hiddenTargetGroupID
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
