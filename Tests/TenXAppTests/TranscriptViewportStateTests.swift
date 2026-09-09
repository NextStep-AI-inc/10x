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

@MainActor @Test func visibleTargetsUseTranscriptOrderInsteadOfCallbackOrder() {
    let viewport = TranscriptViewportState()

    viewport.observeVisibleTargets(
        ["message:third", "message:second"],
        orderedIDs: ["message:first", "message:second", "message:third"],
        isUserScrolling: true)

    #expect(viewport.anchorID == "message:second")
}

@MainActor @Test func initialVisibilityDoesNotOverwriteSavedReadingPosition() {
    let viewport = TranscriptViewportState()
    viewport.anchorID = "message:saved"

    viewport.observeVisibleTargets(
        ["message:first"],
        orderedIDs: ["message:first", "message:saved"],
        isUserScrolling: false)

    #expect(viewport.anchorID == "message:saved")
}

@Test func restorationUsesVisibleTargetOrItsVisibleToolGroup() {
    #expect(TranscriptViewportState.restorationTarget(
        anchorID: "message:saved",
        isFollowingLatest: false,
        hasSearchRequest: false,
        visibleIDs: ["message:saved"],
        hiddenTargetGroupID: nil) == "message:saved")
    #expect(TranscriptViewportState.restorationTarget(
        anchorID: "tool:one",
        isFollowingLatest: false,
        hasSearchRequest: false,
        visibleIDs: ["tool-group-one"],
        hiddenTargetGroupID: "tool-group-one") == "tool-group-one")
    #expect(TranscriptViewportState.restorationTarget(
        anchorID: "message:missing",
        isFollowingLatest: false,
        hasSearchRequest: false,
        visibleIDs: ["message:other"],
        hiddenTargetGroupID: nil) == nil)
}

@Test func searchAndFollowTakePrecedenceOverReadingPositionRestoration() {
    #expect(TranscriptViewportState.restorationTarget(
        anchorID: "message:saved",
        isFollowingLatest: false,
        hasSearchRequest: true,
        visibleIDs: ["message:saved"],
        hiddenTargetGroupID: nil) == nil)
    #expect(TranscriptViewportState.restorationTarget(
        anchorID: "message:saved",
        isFollowingLatest: true,
        hasSearchRequest: false,
        visibleIDs: ["message:saved"],
        hiddenTargetGroupID: nil) == nil)
}

private func geometry(offset: CGFloat, contentHeight: CGFloat) -> TranscriptViewportGeometry {
    TranscriptViewportGeometry(
        offset: offset,
        contentHeight: contentHeight,
        containerSize: CGSize(width: 800, height: 300))
}
