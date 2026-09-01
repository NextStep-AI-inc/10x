import Foundation
import SwiftUI

struct ProviderUsageRingMetric: Equatable {
    let diameter: CGFloat
    let lineWidth: CGFloat
}

enum ProviderUsageRingGeometry {
    static let diameter: CGFloat = 54
    static let coreDiameter: CGFloat = 18

    static func coreDiameter(for outerDiameter: CGFloat) -> CGFloat {
        coreDiameter * outerDiameter / diameter
    }

    /// Outer edge of the outermost ring actually drawn — the wheel's visible
    /// boundary, which is smaller than `outerDiameter`. Every ring is a stroke
    /// centered on its own radius, and the outermost radius plus half a line
    /// width still stops short of the frame the wheel is laid out in, so the
    /// wheel's ink never reaches its own edge. Anything meant to sit flush
    /// against a wheel has to measure from here: drawn at `outerDiameter`
    /// instead it floats clear of the wheel, and whatever is behind shows
    /// through the gap between the two.
    static func visibleDiameter(
        limitCount: Int,
        outerDiameter: CGFloat = diameter
    ) -> CGFloat {
        guard let outermost = metrics(
            limitCount: limitCount, outerDiameter: outerDiameter).last
        else { return outerDiameter }
        return outermost.diameter + outermost.lineWidth
    }

    static func metrics(
        limitCount: Int,
        outerDiameter: CGFloat = diameter
    ) -> [ProviderUsageRingMetric] {
        guard limitCount > 0 else { return [] }
        let scaledCoreDiameter = coreDiameter(for: outerDiameter)
        let availableRadius = (outerDiameter - scaledCoreDiameter) / 2
        let slotWidth = availableRadius / CGFloat(limitCount)
        let lineWidth = slotWidth * 0.68

        return (0..<limitCount).map { index in
            let radius = scaledCoreDiameter / 2 + slotWidth * (CGFloat(index) + 0.5)
            return ProviderUsageRingMetric(diameter: radius * 2, lineWidth: lineWidth)
        }
    }
}

enum ProviderUsageWheelPresentationMode: Equatable, Sendable {
    case providerOnly
    case account(ProviderUsageState)

    var showsPlaceholderTrack: Bool {
        switch self {
        case .providerOnly, .account(.available):
            false
        case .account(.loading), .account(.unavailable):
            true
        }
    }

    func renderedRingCount(limitCount: Int) -> Int {
        showsPlaceholderTrack ? 1 : max(0, limitCount)
    }

    func activityCountText(activeCount: Int) -> String? {
        let normalizedCount = max(0, activeCount)
        if self == .providerOnly, normalizedCount == 0 {
            return nil
        }
        return "\(normalizedCount)"
    }
}

struct ProviderUsageWheelView: View {
    let provider: ProviderUsageProvider
    let activeCount: Int
    let diameter: CGFloat
    let showsProviderLabel: Bool
    let presentationMode: ProviderUsageWheelPresentationMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        provider: ProviderUsageProvider,
        activeCount: Int,
        isGrayscale: Bool,
        diameter: CGFloat = ProviderUsageRingGeometry.diameter,
        showsProviderLabel: Bool = true,
        presentationMode: ProviderUsageWheelPresentationMode = .providerOnly
    ) {
        self.provider = provider
        self.activeCount = activeCount
        self.diameter = diameter
        self.showsProviderLabel = showsProviderLabel
        self.presentationMode = presentationMode
    }

    private var ringLimits: [ProviderUsageLimit] {
        provider.ringLimits
    }

    private var metrics: [ProviderUsageRingMetric] {
        ProviderUsageRingGeometry.metrics(
            limitCount: presentationMode.renderedRingCount(limitCount: ringLimits.count),
            outerDiameter: diameter)
    }

    private var activityCoreDiameter: CGFloat {
        ProviderUsageRingGeometry.coreDiameter(for: diameter)
    }

    private var wheelFillDiameter: CGFloat {
        ProviderUsageRingGeometry.visibleDiameter(
            limitCount: presentationMode.renderedRingCount(limitCount: ringLimits.count),
            outerDiameter: diameter)
    }

    /// Below this the core is under ~13pt and the abbreviation crowds the row,
    /// so the inline-composer size drops both and reads as rings alone.
    private var showsText: Bool {
        diameter >= 40
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(TenXPalette.color(TenXPalette.canvasHex))
                    .frame(width: wheelFillDiameter, height: wheelFillDiameter)

                if presentationMode.showsPlaceholderTrack, let metric = metrics.first {
                    ringTrack(metric: metric)
                } else {
                    ForEach(ringLimits.indices, id: \.self) { index in
                        ring(limit: ringLimits[index], metric: metrics[index])
                    }
                }

                activityPulse
                activityCore
            }
            .frame(
                width: diameter,
                height: diameter)

            if showsProviderLabel, showsText {
                Text(provider.abbreviation)
                    .font(TenXTypography.mono(size: 9, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
        }
        .accessibilityElement(children: .ignore)
    }

    private func ring(limit: ProviderUsageLimit, metric: ProviderUsageRingMetric) -> some View {
        ZStack {
            ringTrack(metric: metric)
            Circle()
                .trim(from: 0, to: limit.normalizedFraction)
                .stroke(
                    progressColor(for: limit),
                    style: StrokeStyle(lineWidth: metric.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: metric.diameter, height: metric.diameter)
    }

    private func ringTrack(metric: ProviderUsageRingMetric) -> some View {
        Circle()
            .stroke(
                TenXPalette.color(TenXPalette.separatorHex),
                style: StrokeStyle(lineWidth: metric.lineWidth, lineCap: .round))
            .frame(width: metric.diameter, height: metric.diameter)
    }

    @ViewBuilder
    private var activityPulse: some View {
        if activeCount > 0 {
            if reduceMotion {
                pulseOutline
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                    let phase = (sin(context.date.timeIntervalSinceReferenceDate * 3) + 1) / 2
                    pulseOutline
                        .scaleEffect(1 + 0.3 * phase)
                        .opacity(0.25 + 0.3 * phase)
                }
            }
        }
    }

    private var pulseOutline: some View {
        Circle()
            .stroke(TenXPalette.color(TenXPalette.cyanHex), lineWidth: 1)
            .frame(
                width: activityCoreDiameter,
                height: activityCoreDiameter)
    }

    private var activityCore: some View {
        Circle()
            .fill(activeCount > 0
                ? TenXPalette.color(TenXPalette.nearBlackHex)
                : TenXPalette.color(TenXPalette.separatorHex))
            .frame(
                width: activityCoreDiameter,
                height: activityCoreDiameter)
            .overlay {
                if showsText,
                   let countText = presentationMode.activityCountText(activeCount: activeCount) {
                    Text(countText)
                        .font(TenXTypography.mono(size: 9, weight: .semibold))
                        .foregroundStyle(activeCount > 0
                            ? TenXPalette.onEmphasis
                            : TenXPalette.color(TenXPalette.mutedTextHex))
                }
            }
    }

    private func progressColor(for limit: ProviderUsageLimit) -> Color {
        switch limit.tone {
        case .standard:
            return TenXPalette.color(TenXPalette.cyanHex)
        case .warning:
            return TenXPalette.color(TenXPalette.yellowHex)
        case .exhausted:
            return TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}
