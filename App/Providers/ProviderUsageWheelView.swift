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

struct ProviderUsageWheelView: View {
    let provider: ProviderUsageProvider
    let activeCount: Int
    let isGrayscale: Bool
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        provider: ProviderUsageProvider,
        activeCount: Int,
        isGrayscale: Bool,
        diameter: CGFloat = ProviderUsageRingGeometry.diameter
    ) {
        self.provider = provider
        self.activeCount = activeCount
        self.isGrayscale = isGrayscale
        self.diameter = diameter
    }

    private var ringLimits: [ProviderUsageLimit] {
        provider.ringLimits
    }

    private var metrics: [ProviderUsageRingMetric] {
        ProviderUsageRingGeometry.metrics(limitCount: ringLimits.count, outerDiameter: diameter)
    }

    private var activityCoreDiameter: CGFloat {
        ProviderUsageRingGeometry.coreDiameter(for: diameter)
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
                width: diameter,
                height: diameter)

            Text(provider.abbreviation)
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .accessibilityElement(children: .ignore)
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
