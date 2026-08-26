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
        let activityDescription: String
        switch activeCount {
        case ...0:
            activityDescription = "No active sessions"
        case 1:
            activityDescription = "1 active session"
        default:
            activityDescription = "\(activeCount) active sessions"
        }

        return ([provider.name, activityDescription] + provider.ringLimits.map(limitSummary))
            .joined(separator: ", ")
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
