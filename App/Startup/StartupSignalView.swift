import SwiftUI

struct StartupSignalGeometry {
    static let waveWidth: CGFloat = 160

    let width: CGFloat
    let midY: CGFloat
    let amplitude: CGFloat

    var waveStart: CGPoint {
        CGPoint(x: max(0, width - Self.waveWidth), y: midY)
    }

    func wavePoint(progress: CGFloat) -> CGPoint {
        CGPoint(
            x: waveStart.x + Self.waveWidth * progress,
            y: midY + CGFloat(sin(Double(progress) * 2 * .pi)) * amplitude)
    }
}

enum StartupSignalMotion {
    static func amplitude(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 16 }
        return CGFloat(16 + 2 * sin(elapsed * 2 * .pi / 2.8))
    }

    static func progress(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return CGFloat((elapsed / 1.8).truncatingRemainder(dividingBy: 1))
    }
}

struct StartupSignalView: View {
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.startupSignalReduceMotionOverride) private var reduceMotionOverride
    @State private var startDate = Date()
    @State private var frozenElapsed: TimeInterval = 0

    var body: some View {
        let reduceMotion = reduceMotionOverride ?? systemReduceMotion
        let shouldAnimate = isAnimating && !reduceMotion

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !shouldAnimate)) { context in
            let liveElapsed = context.date.timeIntervalSince(startDate)
            let elapsed = shouldAnimate ? liveElapsed : frozenElapsed
            let amplitude = StartupSignalMotion.amplitude(
                elapsed: reduceMotion ? 0 : elapsed,
                reduceMotion: reduceMotion)
            let progress = StartupSignalMotion.progress(
                elapsed: reduceMotion ? 0 : elapsed,
                reduceMotion: reduceMotion)

            ZStack {
                StartupSignalShape(amplitude: amplitude)
                    .stroke(
                        TenXPalette.color(TenXPalette.nearBlackHex),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                travelingSegment(amplitude: amplitude, progress: progress)
            }
            .onChange(of: shouldAnimate, initial: true) { _, newValue in
                if reduceMotion {
                    startDate = context.date
                    frozenElapsed = 0
                } else if newValue {
                    startDate = context.date.addingTimeInterval(-frozenElapsed)
                }
            }
            .onChange(of: liveElapsed) { _, newValue in
                guard shouldAnimate else { return }
                frozenElapsed = newValue
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func travelingSegment(amplitude: CGFloat, progress: CGFloat) -> some View {
        let segmentLength: CGFloat = 0.14
        let start = progress
        let end = start + segmentLength
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        let color = TenXPalette.color(TenXPalette.cyanHex)

        if end <= 1 {
            StartupSignalShape(amplitude: amplitude)
                .trim(from: start, to: end)
                .stroke(color, style: style)
        } else {
            StartupSignalShape(amplitude: amplitude)
                .trim(from: start, to: 1)
                .stroke(color, style: style)
            StartupSignalShape(amplitude: amplitude)
                .trim(from: 0, to: end - 1)
                .stroke(color, style: style)
        }
    }
}

private struct StartupSignalReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var startupSignalReduceMotionOverride: Bool? {
        get { self[StartupSignalReduceMotionOverrideKey.self] }
        set { self[StartupSignalReduceMotionOverrideKey.self] = newValue }
    }
}

private struct StartupSignalShape: Shape {
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        let geometry = StartupSignalGeometry(
            width: rect.width,
            midY: rect.midY,
            amplitude: amplitude)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: geometry.waveStart)
        for index in 1...64 {
            path.addLine(to: geometry.wavePoint(progress: CGFloat(index) / 64))
        }
        return path
    }
}
