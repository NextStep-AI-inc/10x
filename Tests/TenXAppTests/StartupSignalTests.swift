import CoreGraphics
import Testing
@testable import TenXApp

@Test func startupSignalUsesOneCenteredSineWaveWithPinnedEndpoints() {
    let geometry = StartupSignalGeometry(width: 640, midY: 24, amplitude: 16)

    #expect(geometry.waveStart.x == 480)
    #expect(geometry.wavePoint(progress: 0).y == 24)
    #expect(abs(geometry.wavePoint(progress: 0.25).y - 40) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 0.5).y - 24) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 0.75).y - 8) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 1).y - 24) < 0.001)
}

@Test func signalMotionBreathesAroundSixteenPointsAndFreezesForReducedMotion() {
    #expect(StartupSignalMotion.amplitude(elapsed: 0, reduceMotion: false) == 16)
    #expect(StartupSignalMotion.amplitude(elapsed: 0.7, reduceMotion: false) <= 18)
    #expect(StartupSignalMotion.amplitude(elapsed: 0.7, reduceMotion: false) >= 14)
    #expect(StartupSignalMotion.amplitude(elapsed: 100, reduceMotion: true) == 16)
    #expect(StartupSignalMotion.progress(elapsed: 100, reduceMotion: true) == 0)
}
