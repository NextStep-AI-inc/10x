import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import TenXApp

@Test func startupSignalEntersSmoothlyAndGrowsIntoAContinuousRipple() {
    let geometry = StartupSignalGeometry(width: 640, midY: 24, amplitude: 18)

    #expect(geometry.waveStart.x == 465)
    #expect(geometry.wavePoint(progress: 0).y == 24)
    #expect(abs(geometry.wavePoint(progress: 0.02).y - 24) < 0.02)
    #expect(abs(geometry.wavePoint(progress: 0.25).y - 24) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 0.5).y - 24) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 0.75).y - 24) < 0.001)
    #expect(abs(geometry.wavePoint(progress: 1).y - 24) < 0.001)

    let firstPeak = geometry.wavePoint(progress: 0.125).y - 24
    let secondPeak = 24 - geometry.wavePoint(progress: 0.375).y
    let thirdPeak = geometry.wavePoint(progress: 0.625).y - 24
    let fourthPeak = 24 - geometry.wavePoint(progress: 0.875).y
    #expect(firstPeak > 5 && firstPeak < 6)
    #expect(secondPeak > 10 && secondPeak < 12)
    #expect(thirdPeak > 13 && thirdPeak < 15)
    #expect(fourthPeak > 16 && fourthPeak < 18)
}

@Test func signalMotionKeepsTheWaveFixedAndFreezesTravelForReducedMotion() {
    #expect(StartupSignalMotion.amplitude(elapsed: 0, reduceMotion: false) == 18)
    #expect(StartupSignalMotion.amplitude(elapsed: 0.7, reduceMotion: false) == 18)
    #expect(StartupSignalMotion.amplitude(elapsed: 100, reduceMotion: true) == 18)
    #expect(StartupSignalMotion.progress(elapsed: 100, reduceMotion: true) == 0)
}

@MainActor
@Test func recoverySignalRendersRedAcrossTheBaseline() throws {
    let state = StartupState()
    let attempt = UUID()
    state.beginAttempt(id: attempt)
    state.markReady(.runtime, attemptID: attempt)
    state.markLoading(.sessions, attemptID: attempt)
    state.enterRecovery(attemptID: attempt)
    let size = CGSize(width: 640, height: 400)
    let root = SplashView(
        state: state,
        buildVersion: "0.1.0",
        onRetry: {},
        onContinue: {})
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
        .environment(\.startupSignalReduceMotionOverride, true)
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: .aqua)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        Issue.record("Unable to allocate startup signal bitmap")
        return
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    let sampleX = Int(100 * scale)
    let baselineY = Int(272 * scale)
    let hasRedPixel = ((baselineY - 4)...(baselineY + 4)).contains { sampleY in
        guard let color = bitmap.colorAt(x: sampleX, y: sampleY)?.usingColorSpace(.sRGB) else {
            return false
        }
        return color.redComponent > 0.8
            && color.greenComponent < 0.4
            && color.blueComponent < 0.3
    }

    #expect(hasRedPixel)
}
