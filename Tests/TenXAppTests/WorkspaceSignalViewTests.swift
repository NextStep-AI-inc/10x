import CoreGraphics
import Foundation
import Testing
@testable import TenXApp

@Test func signalWaveUsesTheLast175PointsAtAnyWidth() {
    for width: CGFloat in [320, 640, 1200] {
        let geometry = StartupSignalGeometry(width: width, midY: 20, amplitude: 18)
        #expect(geometry.waveStart.x == width - 175)
        #expect(geometry.wavePoint(progress: 1).x == width)
    }
}

@Test func workingShimmerStaysOnRemainderAndOpeningUsesWholePath() {
    #expect(WorkspaceSignalMotion.shimmerRange(status: .opening, contextFraction: 0.5) == 0...1)
    #expect(WorkspaceSignalMotion.shimmerRange(status: .working, contextFraction: 0.5) == 0.5...1)
    #expect(WorkspaceSignalMotion.shimmerRange(status: .backgroundWorking(2), contextFraction: 0.5) == 0...1)
    #expect(WorkspaceSignalMotion.shimmerRange(status: .ready, contextFraction: 0.5) == nil)
    #expect(WorkspaceSignalMotion.shimmerRange(status: .working, contextFraction: 1) == nil)
}

@Test func reverseSweepCapsWhileWaitingAndRevealStartsAtZero() {
    #expect(WorkspaceSignalMotion.sweepCoverage(elapsed: 0, reduceMotion: false) == 0)
    let early = WorkspaceSignalMotion.sweepCoverage(elapsed: 0.5, reduceMotion: false)
    let late = WorkspaceSignalMotion.sweepCoverage(elapsed: 10, reduceMotion: false)
    #expect(early > 0)
    #expect(late > early)
    #expect(late < 1)
    #expect(WorkspaceSignalMotion.revealFraction(progress: 0, target: 0.98) == 0)
    #expect(WorkspaceSignalMotion.revealFraction(progress: 1, target: 0.98) == 0.98)
    #expect(WorkspaceSignalMotion.revealDuration == 0.75)
}

@Test func reduceMotionRemovesTravel() {
    #expect(WorkspaceSignalMotion.sweepCoverage(elapsed: 10, reduceMotion: true) == 0)
    #expect(WorkspaceSignalMotion.shimmerRange(status: .needsInput, contextFraction: 0.5) == nil)
}

@Test func measuredNumberWaitsForCoverThenFadesWithReveal() {
    let start = Date(timeIntervalSince1970: 1_000)
    let timing = WorkspaceSignalRevealTiming(generation: 7, start: start, finishDuration: 0.2)
    #expect(timing.opacity(at: start, reduceMotion: false) == 0)
    #expect(timing.opacity(at: start.addingTimeInterval(0.2), reduceMotion: false) < 0.001)
    #expect(abs(timing.opacity(at: start.addingTimeInterval(0.575), reduceMotion: false) - 0.5) < 0.001)
    #expect(timing.opacity(at: start.addingTimeInterval(0.95), reduceMotion: false) == 1)
    #expect(timing.opacity(at: start, reduceMotion: true) == 1)
}
