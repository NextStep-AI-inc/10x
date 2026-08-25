import Foundation

struct ProviderUsageProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let limits: [ProviderUsageLimit]
}

struct ProviderUsageLimit: Identifiable, Equatable {
    enum Tone: Equatable {
        case standard
        case warning
        case exhausted
    }

    let id: String
    let label: String
    let percentage: Int
    let resetWindow: String

    var normalizedFraction: Double {
        Double(min(max(percentage, 0), 100)) / 100
    }

    var tone: Tone {
        if percentage <= 0 { return .exhausted }
        if percentage <= 20 { return .warning }
        return .standard
    }
}
