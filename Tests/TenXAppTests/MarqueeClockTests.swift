import Testing
@testable import TenXApp

@Test func marqueePauseResumesWithoutElapsedJump() {
    var clock = MarqueeClock(at: 10)

    #expect(abs(clock.elapsed(at: 13.2) - 3.2) < 0.001)
    clock.setPaused(true, at: 13.2)
    let pausedElapsed = clock.elapsed(at: 33.2)
    let pausedFrame = MarqueeMotion.frame(
        elapsed: pausedElapsed,
        overflow: 160,
        isRightToLeft: false)
    #expect(abs(pausedElapsed - 3.2) < 0.001)
    #expect(abs(pausedFrame.offset - -80) < 0.001)

    clock.setPaused(false, at: 33.2)
    let resumedElapsed = clock.elapsed(at: 34.2)
    let resumedFrame = MarqueeMotion.frame(
        elapsed: resumedElapsed,
        overflow: 160,
        isRightToLeft: false)
    #expect(abs(resumedElapsed - 4.2) < 0.001)
    #expect(abs(resumedFrame.offset - -120) < 0.001)
}

@Test func marqueeClockRepeatedEventsAreIdempotentAndResetStartsOver() {
    var clock = MarqueeClock(at: 10)
    clock.setPaused(true, at: 13)
    clock.setPaused(true, at: 30)
    #expect(clock.elapsed(at: 40) == 3)

    clock.setPaused(false, at: 40)
    clock.setPaused(false, at: 50)
    #expect(clock.elapsed(at: 51) == 14)

    clock.reset(at: 51)
    #expect(clock.elapsed(at: 51) == 0)
    #expect(clock.elapsed(at: 52) == 1)

    clock.setPaused(true, at: 52)
    clock.reset(at: 80)
    #expect(clock.elapsed(at: 100) == 0)
}
