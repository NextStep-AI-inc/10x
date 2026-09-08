import CoreGraphics
import Testing
@testable import TenXApp

@MainActor @Test func transcriptContentGrowthKeepsFollowingWithoutUserScroll() {
    let viewport = TranscriptViewportState()
    let previous = geometry(offset: 600, contentHeight: 900)
    let grown = geometry(offset: 600, contentHeight: 1_200)

    viewport.observe(from: previous, to: grown, isUserScrolling: false)

    #expect(viewport.isFollowingLatest)
}

@MainActor @Test func userScrollingUpReleasesTranscriptFollowing() {
    let viewport = TranscriptViewportState()
    let previous = geometry(offset: 400, contentHeight: 900)
    let scrolledUp = geometry(offset: 320, contentHeight: 900)

    viewport.observe(from: previous, to: scrolledUp, isUserScrolling: true)

    #expect(!viewport.isFollowingLatest)
}

@MainActor @Test func userReturningToBottomReenablesTranscriptFollowing() {
    let viewport = TranscriptViewportState()
    viewport.isFollowingLatest = false
    let previous = geometry(offset: 320, contentHeight: 900)
    let bottom = geometry(offset: 600, contentHeight: 900)

    viewport.observe(from: previous, to: bottom, isUserScrolling: true)

    #expect(viewport.isFollowingLatest)
}

private func geometry(offset: CGFloat, contentHeight: CGFloat) -> TranscriptViewportGeometry {
    TranscriptViewportGeometry(
        offset: offset,
        contentHeight: contentHeight,
        containerSize: CGSize(width: 800, height: 300))
}
