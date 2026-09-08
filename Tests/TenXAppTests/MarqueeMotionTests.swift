import CoreGraphics
import Testing
@testable import TenXApp

@Test func marqueeHoldsTravelsReturnsAndWrapsContinuously() {
    let samples: [(Double, CGFloat)] = [
        (0, 0),
        (1.2, 0),
        (3.2, -80),
        (5.2, -160),
        (6.0, -160),
        (8.4, -80),
        (10.4, 0),
    ]

    for (time, expected) in samples {
        let frame = MarqueeMotion.frame(
            elapsed: time,
            overflow: 160,
            isRightToLeft: false)
        #expect(abs(frame.offset - expected) < 0.001)
    }
}

@Test func marqueeFitAndInvalidGeometryStayStill() {
    let invalidSamples: [(elapsed: Double, overflow: CGFloat)] = [
        (4, 0),
        (4, -20),
        (.nan, 160),
        (.infinity, 160),
        (4, .infinity),
        (4, .nan),
    ]

    for sample in invalidSamples {
        let frame = MarqueeMotion.frame(
            elapsed: sample.elapsed,
            overflow: sample.overflow,
            isRightToLeft: false)
        #expect(frame.offset == 0)
        #expect(frame.fadesLeading == false)
        #expect(frame.fadesTrailing == false)
    }

    let negativeElapsed = MarqueeMotion.frame(
        elapsed: -10,
        overflow: 160,
        isRightToLeft: false)
    #expect(negativeElapsed.offset == 0)
    #expect(negativeElapsed.fadesLeading == false)
    #expect(negativeElapsed.fadesTrailing)
}

@Test func marqueeRTLReversesDirection() {
    let leftToRight = MarqueeMotion.frame(
        elapsed: 3.2,
        overflow: 160,
        isRightToLeft: false)
    let rightToLeft = MarqueeMotion.frame(
        elapsed: 3.2,
        overflow: 160,
        isRightToLeft: true)

    #expect(leftToRight.offset == -80)
    #expect(rightToLeft.offset == 80)
    #expect(rightToLeft.fadesLeading == leftToRight.fadesLeading)
    #expect(rightToLeft.fadesTrailing == leftToRight.fadesTrailing)
}

@Test func marqueeBoundariesRemainContinuousAndSetLogicalFades() {
    let samples: [(time: Double, offset: CGFloat, leading: Bool, trailing: Bool)] = [
        (1.199, 0, false, true),
        (1.2, 0, false, true),
        (1.201, -0.04, true, true),
        (5.199, -159.96, true, true),
        (5.2, -160, true, false),
        (5.201, -160, true, false),
        (6.399, -160, true, false),
        (6.4, -160, true, false),
        (6.401, -159.96, true, true),
        (10.399, -0.04, true, true),
        (10.4, 0, false, true),
        (10.401, 0, false, true),
    ]

    for sample in samples {
        let frame = MarqueeMotion.frame(
            elapsed: sample.time,
            overflow: 160,
            isRightToLeft: false)
        #expect(frame.offset.isFinite)
        #expect(frame.offset >= -160 && frame.offset <= 0)
        #expect(abs(frame.offset - sample.offset) < 0.001)
        #expect(frame.fadesLeading == sample.leading)
        #expect(frame.fadesTrailing == sample.trailing)
    }
}
