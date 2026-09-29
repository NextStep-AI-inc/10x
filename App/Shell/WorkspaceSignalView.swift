import SwiftUI

enum WorkspaceSignalMotion {
    static let revealDuration: TimeInterval = 0.75
    static let finishDuration: TimeInterval = 0.35

    static func sweepCoverage(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return 0.94 * CGFloat(1 - exp(-max(elapsed, 0) / 1.3))
    }

    static func revealFraction(progress: Double, target: CGFloat) -> CGFloat {
        min(max(CGFloat(progress), 0), 1) * min(max(target, 0), 1)
    }

    static func shimmerRange(
        status: WorkspaceSignalStatus,
        contextFraction: CGFloat
    ) -> ClosedRange<CGFloat>? {
        switch status {
        case .opening, .backgroundWorking:
            return 0...1
        case .working:
            let start = min(max(contextFraction, 0), 1)
            return start < 1 ? start...1 : nil
        default:
            return nil
        }
    }
}

struct WorkspaceSignalRevealTiming {
    let generation: UInt64
    let start: Date
    let finishDuration: TimeInterval

    func opacity(at date: Date, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        return min(max((date.timeIntervalSince(start) - finishDuration)
            / WorkspaceSignalMotion.revealDuration, 0), 1)
    }
}

struct WorkspaceSignalView: View {
    let presentation: WorkspaceSignalPresentation
    let compactionPhase: SessionCompactionSignalPhase
    let onRevealComplete: (UInt64) -> Void
    var onRevealStart: (WorkspaceSignalRevealTiming) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.workspaceSignalReduceMotionOverride) private var reduceMotionOverride
    @State private var sweepStartedAt = Date()
    @State private var finishStartedAt = Date()
    @State private var finishFromCoverage: CGFloat = 0
    @State private var finishDuration: TimeInterval = WorkspaceSignalMotion.finishDuration
    @State private var preRevealFraction: CGFloat = 0
    @State private var configuredPhase: SessionCompactionSignalPhase = .none

    private let amplitude: CGFloat = 18
    private let lineWidth: CGFloat = 2

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    private var phaseKey: String {
        switch compactionPhase {
        case .none: "none"
        case .sweeping: "sweeping"
        case .refreshing: "refreshing"
        case .revealing(let generation, _): "revealing-\(generation)-\(reduceMotion)"
        }
    }

    private var isCompactionVisible: Bool {
        switch presentation.status {
        case .compacting, .refreshingContext, .working, .ready, .nearLimit:
            return true
        default:
            return false
        }
    }

    private var isTraveling: Bool {
        guard !reduceMotion else { return false }
        if isCompactionVisible && compactionPhase != .none { return true }
        return WorkspaceSignalMotion.shimmerRange(
            status: presentation.status,
            contextFraction: CGFloat(presentation.contextFraction ?? 0)) != nil
            || presentation.status == .retrying
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isTraveling)) { timeline in
            GeometryReader { geometry in
                let rect = CGRect(origin: .zero, size: geometry.size)
                let shape = StartupSignalShape(amplitude: amplitude)
                let target = CGFloat(presentation.contextFraction ?? 0)
                let fraction = displayedContextFraction(at: timeline.date, target: target)
                let coverage = coveredFraction(at: timeline.date)
                let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

                ZStack {
                    shape.stroke(TenXPalette.color(TenXPalette.nearBlackHex), style: style)

                    if fraction > 0 && presentation.status != .opening {
                        shape.trim(from: 0, to: fraction)
                            .stroke(TenXPalette.color(TenXPalette.cyanHex), style: style)
                    }

                    if let statusColor = statusColor {
                        let start = statusStartFraction(path: shape.path(in: rect), contextFraction: target)
                        shape.trim(from: start, to: 1)
                            .stroke(statusColor, style: style)
                    }

                    if presentation.status == .nearLimit, presentation.contextFraction != nil {
                        let endpoint = shape.path(in: rect)
                            .trimmedPath(from: 0, to: target).currentPoint
                        Circle()
                            .fill(TenXPalette.color(TenXPalette.cyanHex))
                            .frame(width: 6, height: 6)
                            .position(endpoint ?? .zero)
                    }

                    if isCompactionVisible && compactionPhase != .none && !reduceMotion {
                        shape.trim(from: 1 - coverage, to: 1)
                            .stroke(TenXPalette.color(TenXPalette.nearBlackHex), style: style)
                    }

                    if !reduceMotion {
                        shimmer(shape: shape, date: timeline.date, contextFraction: target, style: style)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .onChange(of: compactionPhase, initial: true) { oldValue, newValue in
            let now = Date()
            switch newValue {
            case .sweeping:
                sweepStartedAt = now
                preRevealFraction = CGFloat(presentation.contextFraction ?? 0)
            case .refreshing, .revealing:
                finishFromCoverage = coverage(for: oldValue, at: now)
                finishStartedAt = now
                finishDuration = WorkspaceSignalMotion.finishDuration * Double(1 - finishFromCoverage)
                if oldValue == .none {
                    preRevealFraction = CGFloat(presentation.contextFraction ?? 0)
                }
                if case .revealing(let generation, _) = newValue {
                    onRevealStart(WorkspaceSignalRevealTiming(
                        generation: generation,
                        start: now,
                        finishDuration: finishDuration))
                }
            case .none:
                break
            }
            configuredPhase = newValue
        }
        .task(id: phaseKey) {
            guard case .revealing(let generation, _) = compactionPhase else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(finishDuration + WorkspaceSignalMotion.revealDuration))
            }
            guard !Task.isCancelled,
                  case .revealing(let currentGeneration, _) = compactionPhase,
                  currentGeneration == generation else { return }
            onRevealComplete(generation)
        }
    }

    private var statusColor: Color? {
        switch presentation.status {
        case .needsInput, .retrying, .nearLimit:
            TenXPalette.color(TenXPalette.yellowHex)
        case .failed:
            TenXPalette.color(TenXPalette.signalRedHex)
        default:
            nil
        }
    }

    private func statusStartFraction(path: Path, contextFraction: CGFloat) -> CGFloat {
        let length = path.boundingRect.width
        let minimumSpan = length > 0 ? min(80 / length, 1) : 1
        return min(contextFraction, 1 - minimumSpan)
    }

    private func coverage(for phase: SessionCompactionSignalPhase, at date: Date) -> CGFloat {
        switch phase {
        case .none:
            return 0
        case .sweeping:
            return WorkspaceSignalMotion.sweepCoverage(
                elapsed: date.timeIntervalSince(sweepStartedAt), reduceMotion: reduceMotion)
        case .refreshing, .revealing:
            let progress = finishDuration > 0
                ? min(max(date.timeIntervalSince(finishStartedAt) / finishDuration, 0), 1)
                : 1
            return finishFromCoverage + (1 - finishFromCoverage) * CGFloat(progress)
        }
    }

    private func coveredFraction(at date: Date) -> CGFloat {
        guard isCompactionVisible else { return 0 }
        if configuredPhase != compactionPhase {
            return coverage(for: configuredPhase, at: date)
        }
        switch compactionPhase {
        case .none: return 0
        case .sweeping, .refreshing: return coverage(for: compactionPhase, at: date)
        case .revealing:
            let elapsed = date.timeIntervalSince(finishStartedAt) - finishDuration
            if elapsed <= 0 { return coverage(for: compactionPhase, at: date) }
            return max(0, 1 - CGFloat(elapsed / WorkspaceSignalMotion.revealDuration))
        }
    }

    private func displayedContextFraction(at date: Date, target: CGFloat) -> CGFloat {
        guard isCompactionVisible,
              case .revealing = compactionPhase else { return target }
        if reduceMotion { return target }
        if configuredPhase != compactionPhase { return preRevealFraction }
        let elapsed = date.timeIntervalSince(finishStartedAt) - finishDuration
        if elapsed <= 0 { return preRevealFraction }
        return WorkspaceSignalMotion.revealFraction(
            progress: elapsed / WorkspaceSignalMotion.revealDuration, target: target)
    }

    @ViewBuilder
    private func shimmer(
        shape: StartupSignalShape,
        date: Date,
        contextFraction: CGFloat,
        style: StrokeStyle
    ) -> some View {
        let range = WorkspaceSignalMotion.shimmerRange(
            status: presentation.status, contextFraction: contextFraction)
        if let range {
            let width = range.upperBound - range.lowerBound
            let progress = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4)
            let segment = min(width * 0.18, 0.12)
            let start = range.lowerBound + max(0, width - segment) * progress
            shape.trim(from: start, to: start + segment)
                .stroke(TenXPalette.color(TenXPalette.mutedTextHex).opacity(0.42), style: style)
        } else if presentation.status == .retrying {
            let progress = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4)
            let start = min(contextFraction, 0.9) + (1 - min(contextFraction, 0.9)) * progress
            shape.trim(from: start, to: min(start + 0.08, 1))
                .stroke(TenXPalette.color(TenXPalette.canvasHex).opacity(0.45), style: style)
        }
    }
}

private struct WorkspaceSignalReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var workspaceSignalReduceMotionOverride: Bool? {
        get { self[WorkspaceSignalReduceMotionOverrideKey.self] }
        set { self[WorkspaceSignalReduceMotionOverrideKey.self] = newValue }
    }
}
