import OmpKit
import SwiftUI

struct ProviderAccountConnectionRowPresentation: Equatable, Sendable {
    let label: String
    let detail: String?
    let status: String?
    let actionLabel: String
    let accessibilityLabel: String
    let isActionDisabled: Bool

    static func make(
        account: ProviderAccountSummary,
        isPrimary: Bool,
        sessionCount: Int,
        isPendingRemoval: Bool,
        canRemove: Bool = true,
        isRemovalDisabledByTier: Bool = false
    ) -> ProviderAccountConnectionRowPresentation {
        let displayLabel = normalized(account.displayLabel) ?? "Connected account"
        let detail = normalized(account.detailLabel).flatMap { value in
            value == displayLabel ? nil : value
        }
        // This run only ever carries per-account facts (primary, session
        // count, replacement eligibility). A tier-wide removal restriction
        // is stated once for the whole provider section instead — see
        // `ProviderConnectionsView.removalUnavailableReason` — never
        // repeated here on every row.
        var statuses: [String] = []
        if isPrimary { statuses.append("Primary") }
        if sessionCount == 1 {
            statuses.append("In use by 1 session")
        } else if sessionCount > 1 {
            statuses.append("In use by \(sessionCount) sessions")
        }
        if !canRemove { statuses.append("No available replacement") }
        let status = statuses.isEmpty ? nil : statuses.joined(separator: " · ")
        let accessibilityLabel = [displayLabel, detail, status]
            .compactMap { $0 }
            .joined(separator: ", ")
        return ProviderAccountConnectionRowPresentation(
            label: displayLabel,
            detail: detail,
            status: status,
            actionLabel: isPendingRemoval ? "Removing…" : "Remove",
            accessibilityLabel: accessibilityLabel,
            isActionDisabled: isPendingRemoval || !canRemove || isRemovalDisabledByTier)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct ProviderAccountConnectionRowView: View {
    let account: ProviderAccountSummary
    let isPrimary: Bool
    let sessionCount: Int
    let isPendingRemoval: Bool
    let canRemove: Bool
    let isRemovalDisabledByTier: Bool
    let removeButtonFocus: FocusState<String?>.Binding
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.label)
                    .font(TenXTypography.body(size: 13, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                if let detail = presentation.detail {
                    Text(detail)
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                if let status = presentation.status {
                    Text(status)
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
            }
            Spacer(minLength: 16)
            Button(presentation.actionLabel, action: onRemove)
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(TenXPalette.signalRedHex)))
                .disabled(presentation.isActionDisabled)
                .accessibilityLabel("Remove \(presentation.accessibilityLabel)")
                .focused(removeButtonFocus, equals: account.id)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var presentation: ProviderAccountConnectionRowPresentation {
        ProviderAccountConnectionRowPresentation.make(
            account: account,
            isPrimary: isPrimary,
            sessionCount: sessionCount,
            isPendingRemoval: isPendingRemoval,
            canRemove: canRemove,
            isRemovalDisabledByTier: isRemovalDisabledByTier)
    }
}
