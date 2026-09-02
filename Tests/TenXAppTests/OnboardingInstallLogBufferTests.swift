import Testing
@testable import TenXApp

@Suite
struct OnboardingInstallLogBufferTests {
    @MainActor
    @Test
    func installerBufferRetainsAllLinesButPublishesInBatches() {
        let scheduler = ManualLogFlushScheduler()
        let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)

        for index in 0..<1_000 {
            buffer.append("line \(index)")
        }

        #expect(buffer.totalCount == 0)
        #expect(scheduler.scheduledCount == 1)

        scheduler.fireLatest()

        #expect(buffer.totalCount == 1_000)
        #expect(buffer.completeText.split(separator: "\n").count == 1_000)
    }

    @MainActor
    @Test
    func installerTailRevealsOlderLinesOnePageAtATime() {
        let scheduler = ManualLogFlushScheduler()
        let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)

        for index in 0..<1_000 {
            buffer.append("line \(index)")
        }
        scheduler.fireLatest()

        let initialTail = buffer.visibleTail(limit: 200)
        let expandedTail = buffer.visibleTail(limit: 400)

        #expect(initialTail.count == 200)
        #expect(initialTail.first?.text == "line 800")
        #expect(expandedTail.count == 400)
        #expect(expandedTail.first?.text == "line 600")
    }

    @MainActor
    @Test
    func installerLinesKeepAbsoluteIDsWhenOlderPagesAreShown() {
        let scheduler = ManualLogFlushScheduler()
        let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)

        for index in 0..<500 {
            buffer.append("line \(index)")
        }
        scheduler.fireLatest()

        let initialTail = buffer.visibleTail(limit: 200)
        let expandedTail = buffer.visibleTail(limit: 400)

        #expect(initialTail.first?.id == 300)
        #expect(initialTail.last?.id == 499)
        #expect(expandedTail.suffix(200).map(\.id) == initialTail.map(\.id))
    }

    @MainActor
    @Test
    func installerResetInvalidatesLateScheduledCallbacks() {
        let scheduler = ManualLogFlushScheduler()
        let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)

        buffer.append("stale")
        buffer.reset()
        scheduler.fireFirst()

        #expect(buffer.totalCount == 0)
        #expect(buffer.completeText.isEmpty)
    }

    @MainActor
    @Test
    func installerFlushPublishesPendingLinesAndInvalidatesScheduledCallback() {
        let scheduler = ManualLogFlushScheduler()
        let buffer = OnboardingInstallLogBuffer(scheduleFlush: scheduler.schedule)

        buffer.append("one")
        buffer.flush()
        let flushedRevision = buffer.flushRevision
        scheduler.fireFirst()

        #expect(buffer.totalCount == 1)
        #expect(buffer.completeText == "one")
        #expect(buffer.flushRevision == flushedRevision)
    }

    @MainActor
    @Test
    func installerRevealUsesOneFinitePagePerAction() {
        var reveal = ProgressiveReveal(initialLimit: 200, pageSize: 200)

        #expect(reveal.visibleCount(total: 1_000) == 200)
        #expect(reveal.nextPageCount(total: 1_000) == 200)
        reveal.revealNextPage(total: 1_000)
        #expect(reveal.visibleCount(total: 1_000) == 400)
    }
}

@MainActor
private final class ManualLogFlushScheduler {
    private var actions: [@MainActor () -> Void] = []
    private(set) var scheduledCount = 0

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduledCount += 1
        actions.append(action)
    }

    func fireFirst() {
        guard !actions.isEmpty else { return }
        let action = actions.removeFirst()
        action()
    }

    func fireLatest() {
        guard let action = actions.popLast() else { return }
        action()
    }
}
