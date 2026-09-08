import Foundation
import SwiftUI

struct ContextUsageControl: View {
    let usage: SessionContextUsage?
    let breakdown: SessionContextBreakdown?
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void

    @State private var isPresented = false

    private var summary: ContextUsageSummary? {
        ContextUsageSummary(usage: usage, breakdown: breakdown)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                ContextUsageMiniMeter(fillFraction: summary?.fillFraction ?? 0)
                Text(triggerLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .buttonStyle(GhostActionStyle(
            color: TenXPalette.color(TenXPalette.nearBlackHex),
            horizontalPadding: 5))
        .accessibilityLabel("Context window")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows context usage details")
        .accessibilityAddTraits(isPresented ? .isSelected : [])
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ContextUsagePopover(
                summary: summary,
                breakdown: breakdown,
                isLoading: isLoading,
                errorMessage: errorMessage,
                onClose: { isPresented = false },
                onRefresh: onRefresh)
                .task {
                    await onRefresh()
                }
        }
    }

    private var triggerLabel: String {
        if let summary {
            return "Context \(summary.percent.formatted(.number.precision(.fractionLength(0))))%"
        }
        if isLoading { return "Context loading…" }
        return "Context unavailable"
    }

    private var accessibilityValue: String {
        if let summary {
            return "\(summary.percent.formatted(.number.precision(.fractionLength(0)))) percent used"
        }
        return isLoading ? "Loading" : "Unavailable"
    }
}

struct ContextUsageSummary {
    let usedTokens: Int
    let contextWindow: Int
    let remainingTokens: Int
    let percent: Double
    let fillFraction: Double
    let updatedAt: Date

    init?(usage: SessionContextUsage?, breakdown: SessionContextBreakdown?) {
        if let breakdown {
            let capacity = max(0, breakdown.contextWindow)
            let used = max(0, breakdown.usedTokens)
            usedTokens = used
            contextWindow = capacity
            remainingTokens = max(0, capacity - used)
            fillFraction = capacity > 0
                ? min(1, max(0, Double(used) / Double(capacity)))
                : 0
            percent = capacity > 0 ? max(0, Double(used) / Double(capacity) * 100) : 0
            updatedAt = breakdown.updatedAt
        } else if let usage {
            usedTokens = max(0, usage.tokens)
            contextWindow = max(0, usage.contextWindow)
            remainingTokens = max(0, usage.remainingTokens)
            percent = max(0, usage.percent)
            fillFraction = min(1, max(0, usage.fillFraction))
            updatedAt = usage.updatedAt
        } else {
            return nil
        }
    }
}

private struct ContextUsageMiniMeter: View {
    let fillFraction: Double

    private var filledBarCount: Int {
        guard fillFraction > 0 else { return 0 }
        return min(4, Int(ceil(min(1, max(0, fillFraction)) * 4)))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle()
                    .fill(TenXPalette.color(
                        index < filledBarCount
                            ? TenXPalette.cyanHex
                            : TenXPalette.separatorHex))
                    .frame(width: 3, height: 13)
            }
        }
        .frame(width: 18, height: 13, alignment: .leading)
        .accessibilityHidden(true)
    }
}

struct ContextUsagePopover: View {
    let summary: ContextUsageSummary?
    let breakdown: SessionContextBreakdown?
    let isLoading: Bool
    let errorMessage: String?
    let onClose: () -> Void
    let onRefresh: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let summary {
                usageDetails(summary)
            } else if isLoading {
                ProgressView("Loading context usage…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                unavailableState
            }
        }
        .padding(20)
        .frame(minWidth: 260, idealWidth: 334, maxWidth: 334, alignment: .leading)
        .background(TenXPalette.color(TenXPalette.canvasHex))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context window details")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Context window")
                .font(TenXTypography.body(size: 14, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            if isLoading, summary != nil {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Refreshing context usage")
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close context details")
            .accessibilityLabel("Close context details")
        }
        .padding(.bottom, 17)
    }

    private func usageDetails(_ summary: ContextUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(summary.usedTokens.formatted())
                    .font(TenXTypography.body(size: 27, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("/ \(summary.contextWindow.formatted()) tokens")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
            }

            ContextUsageMeter(
                fillFraction: summary.fillFraction,
                categories: breakdown?.categories ?? [],
                contextWindow: summary.contextWindow,
                usedTokens: summary.usedTokens)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    usagePercent(summary)
                    Spacer(minLength: 8)
                    remainingContext(summary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    usagePercent(summary)
                    remainingContext(summary)
                }
            }
            .font(TenXTypography.body(size: 12))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))

            if let breakdown, breakdown.autoCompactBufferTokens > 0 {
                HStack(spacing: 8) {
                    Text("Reserved for compaction")
                    Spacer(minLength: 8)
                    Text("\(breakdown.autoCompactBufferTokens.formatted()) tokens")
                        .monospacedDigit()
                }
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }

            if let breakdown {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(breakdown.categories.prefix(5).enumerated()), id: \.element.id) { index, category in
                        categoryRow(category, index: index)
                    }
                }
                .padding(.top, 14)
            } else if isLoading {
                ProgressView("Loading breakdown…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.top, 12)
            } else {
                Text("Breakdown unavailable")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .padding(.top, 18)
            }

            if let errorMessage, !errorMessage.isEmpty {
                retryState(errorMessage)
                    .padding(.top, 12)
            }

            Text(Self.estimateText(updatedAt: summary.updatedAt))
                .fixedSize(horizontal: false, vertical: true)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(height: 1)
                }
                .padding(.top, 14)
        }
    }

    private func categoryRow(
        _ category: SessionContextBreakdown.Category,
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex).opacity(Self.opacity(for: index)))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(category.label)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(category.tokens.formatted())
                .monospacedDigit()
        }
        .font(TenXTypography.body(size: 12))
        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.label), \(category.tokens.formatted()) tokens")
    }

    private func usagePercent(_ summary: ContextUsageSummary) -> some View {
        Text("\(summary.percent.formatted(.number.precision(.fractionLength(0))))% used")
            .fixedSize(horizontal: true, vertical: false)
    }

    private func remainingContext(_ summary: ContextUsageSummary) -> some View {
        Text("\(summary.remainingTokens.formatted()) context remaining")
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(visibleErrorMessage ?? "Context usage is unavailable.")
                .font(TenXTypography.body(size: 12))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .fixedSize(horizontal: false, vertical: true)
            if visibleErrorMessage != nil {
                retryButton
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
    }

    private func retryState(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(message)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            retryButton
        }
    }

    private var retryButton: some View {
        Button("Try again") {
            Task { await onRefresh() }
        }
        .buttonStyle(GhostActionStyle())
        .disabled(isLoading)
    }

    private var visibleErrorMessage: String? {
        guard let errorMessage, !errorMessage.isEmpty else { return nil }
        return errorMessage
    }

    fileprivate static func opacity(for index: Int) -> Double {
        [1, 0.72, 0.54, 0.36, 0.22][min(max(index, 0), 4)]
    }

    private static func estimateText(updatedAt: Date) -> String {
        "Estimated current context · updated \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ContextUsageMeter: View {
    let fillFraction: Double
    let categories: [SessionContextBreakdown.Category]
    let contextWindow: Int
    let usedTokens: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                if categories.isEmpty {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.cyanHex))
                        .frame(width: geometry.size.width * min(1, max(0, fillFraction)))
                } else {
                    let visibleCategories = Array(categories.prefix(5))
                    let gapWidth = CGFloat(max(0, visibleCategories.count - 1))
                    let availableWidth = max(0, geometry.size.width - gapWidth)
                    ForEach(Array(visibleCategories.enumerated()), id: \.element.id) { index, category in
                        Rectangle()
                            .fill(TenXPalette.color(TenXPalette.cyanHex).opacity(
                                ContextUsagePopover.opacity(for: index)))
                            .frame(width: segmentWidth(
                                tokens: category.tokens,
                                availableWidth: availableWidth))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context used")
        .accessibilityValue("\((fillFraction * 100).formatted(.number.precision(.fractionLength(0)))) percent")
    }

    private func segmentWidth(tokens: Int, availableWidth: CGFloat) -> CGFloat {
        let normalizationTokens = max(contextWindow, usedTokens)
        guard normalizationTokens > 0 else { return 0 }
        return availableWidth * min(
            1,
            max(0, CGFloat(tokens) / CGFloat(normalizationTokens)))
    }
}
