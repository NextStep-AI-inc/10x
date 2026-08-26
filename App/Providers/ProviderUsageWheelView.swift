import Foundation
import SwiftUI

struct ProviderUsageRingMetric: Equatable {
    let diameter: CGFloat
    let lineWidth: CGFloat
}

enum ProviderUsageRingGeometry {
    static let diameter: CGFloat = 54
    static let coreDiameter: CGFloat = 18

    static func metrics(limitCount: Int) -> [ProviderUsageRingMetric] {
        guard limitCount > 0 else { return [] }
        let availableRadius = (diameter - coreDiameter) / 2
        let slotWidth = availableRadius / CGFloat(limitCount)
        let lineWidth = slotWidth * 0.68

        return (0..<limitCount).map { index in
            let radius = coreDiameter / 2 + slotWidth * (CGFloat(index) + 0.5)
            return ProviderUsageRingMetric(diameter: radius * 2, lineWidth: lineWidth)
        }
    }
}

struct ProviderUsageWheelView: View {
    let provider: ProviderUsageProvider
    let activeCount: Int
    let isGrayscale: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ringLimits: [ProviderUsageLimit] {
        provider.ringLimits
    }

    private var metrics: [ProviderUsageRingMetric] {
        ProviderUsageRingGeometry.metrics(limitCount: ringLimits.count)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                ForEach(ringLimits.indices, id: \.self) { index in
                    ring(limit: ringLimits[index], metric: metrics[index])
                }

                activityPulse
                activityCore
            }
            .frame(
                width: ProviderUsageRingGeometry.diameter,
                height: ProviderUsageRingGeometry.diameter)

            Text(provider.abbreviation)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .accessibilityHidden(true)
    }

    private func ring(limit: ProviderUsageLimit, metric: ProviderUsageRingMetric) -> some View {
        ZStack {
            Circle()
                .stroke(
                    TenXPalette.color(TenXPalette.separatorHex),
                    style: StrokeStyle(lineWidth: metric.lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: limit.normalizedFraction)
                .stroke(
                    progressColor(for: limit),
                    style: StrokeStyle(lineWidth: metric.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
                width: ProviderUsageRingGeometry.coreDiameter,
                height: ProviderUsageRingGeometry.coreDiameter)
    }

    private var activityCore: some View {
        Circle()
            .fill(activeCount > 0
                ? TenXPalette.color(TenXPalette.nearBlackHex)
                : TenXPalette.color(TenXPalette.separatorHex))
            .frame(
                width: ProviderUsageRingGeometry.coreDiameter,
                height: ProviderUsageRingGeometry.coreDiameter)
            .overlay {
                if activeCount > 0 {
                    Text("\(activeCount)")
                        .font(TenXTypography.mono(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
    }

    private func progressColor(for limit: ProviderUsageLimit) -> Color {
        if isGrayscale {
            return TenXPalette.color(TenXPalette.mutedTextHex)
        }

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
