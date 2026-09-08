import Foundation

struct ProviderExtensionHello: Sendable, Equatable {
    let contractVersion: Int
}

enum ProviderAccountTier: Sendable, Equatable {
    case providerOnly
    case stockOMP
    case extensionBacked

    static let contractVersion = 1

    /// The extension must fail closed: an incompatible contract degrades to the
    /// stock tier rather than leaving the app half configured.
    static func detect(snapshot: OmpUsageSnapshot, extensionHello: ProviderExtensionHello?) -> Self {
        let hasPerAccountIdentity = snapshot.reports.contains { report in
            ProviderAccountUsageBackend.accountRef(for: report) != nil
        }
        guard hasPerAccountIdentity else { return .providerOnly }
        guard let extensionHello, extensionHello.contractVersion == contractVersion else { return .stockOMP }
        return .extensionBacked
    }

    var supportsRemoval: Bool { self == .extensionBacked }
    var requiresRestartToSwitch: Bool { self == .stockOMP }
}
