import Foundation
import OmpKit

final class ProviderPrimaryPreferenceStore {
    private let defaults: UserDefaults
    private let key = "providerPrimaryAccountRefs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func primaryAccountRef(providerID: String) -> String? {
        primaryAccountRefs()[providerID]
    }

    func setPrimaryAccountRef(_ accountRef: String?, providerID: String) {
        var refs = primaryAccountRefs()
        refs[providerID] = accountRef
        defaults.set(refs, forKey: key)
    }

    @discardableResult
    func repairPrimary(providerID: String, accounts: [ProviderAccountSummary]) -> String? {
        if let primary = primaryAccountRef(providerID: providerID),
           accounts.contains(where: { $0.accountRef == primary && $0.isEligiblePrimary }) {
            return primary
        }

        let replacement = accounts.enumerated()
            .filter { $0.element.isEligiblePrimary }
            .min {
                if $0.element.connectionOrder == $1.element.connectionOrder {
                    return $0.offset < $1.offset
                }
                return $0.element.connectionOrder < $1.element.connectionOrder
            }?
            .element
            .accountRef
        setPrimaryAccountRef(replacement, providerID: providerID)
        return replacement
    }

    private func primaryAccountRefs() -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}

extension ProviderAccountSummary {
    var isEligiblePrimary: Bool {
        availability == .available || availability == .limited
    }
}
