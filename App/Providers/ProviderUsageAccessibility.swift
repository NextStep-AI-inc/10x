import Foundation

enum ProviderUsageAccessibility {
    static func limitLabel(
        provider: String,
        account: String?,
        allowance: String,
        percentage: Int,
        reset: String
    ) -> String {
        let resetDescription: String
        if let resetValue = resetValue(reset) {
            let resetPhrase = resetValue.hasPrefix("in ") ? resetValue : "in \(resetValue)"
            resetDescription = "resets \(resetPhrase)"
        } else {
            resetDescription = "reset unavailable"
        }
        return [
            provider,
            account,
            allowance,
            "\(min(max(percentage, 0), 100)) percent remaining",
            resetDescription,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func displayReset(_ reset: String) -> String {
        resetValue(reset) ?? "Reset unavailable"
    }

    static func wheelValue(provider: ProviderUsageProvider, activeCount: Int) -> String {
        if provider.capability == .accountRouting,
           provider.accounts.count == 1,
           let account = provider.accounts.first {
            return accountWheelValue(account: account, activeCount: activeCount)
        }

        return ([provider.name, activityDescription(activeCount)]
            + provider.ringLimits.map(limitSummary))
            .joined(separator: ", ")
    }

    static func accountWheelLabel(
        provider: String,
        account: ProviderUsageAccount
    ) -> String {
        "\(provider), \(account.label)"
    }

    static func accountWheelValue(
        account: ProviderUsageAccount,
        activeCount: Int
    ) -> String {
        ([account.label, activityDescription(activeCount)] + account.limits.map(limitSummary))
            .joined(separator: ", ")
    }

    private static func activityDescription(_ activeCount: Int) -> String {
        switch activeCount {
        case ...0: "No active sessions"
        case 1: "1 active session"
        default: "\(activeCount) active sessions"
        }
    }

    private static func limitSummary(_ limit: ProviderUsageLimit) -> String {
        let reset = limit.resetWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        let resetDescription: String
        if reset.isEmpty {
            resetDescription = "reset unavailable"
        } else {
            let normalizedReset = reset.hasPrefix("in ") ? reset : "in \(reset)"
            resetDescription = "resets \(normalizedReset)"
        }
        return "\(limit.label), \(min(max(limit.percentage, 0), 100)) percent remaining, \(resetDescription)"
    }

    private static func resetValue(_ reset: String) -> String? {
        let value = reset.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
