import CryptoKit
import Foundation

/// Mirrors stock OMP 18.0.6's `credentialPinHash`
/// (`packages/coding-agent/src/session/credential-pin.ts`, commit
/// `b4e8e856a`): `sha256(provider \0 accountId \0 email \0 orgId \0
/// projectId)`, lowercase hex, with an empty string standing in for any
/// absent field, and `nil` when both `accountId` and `email` are absent.
/// The digest input is OMP's persisted contract, so this value is both our
/// opaque account reference and a pin OMP honors. Changing the join, the
/// field order, or the empty-field convention orphans every recorded pin.
enum ProviderAccountRef {
    static func make(
        providerID: String,
        accountID: String?,
        email: String?,
        orgID: String?,
        projectID: String?
    ) -> String? {
        guard accountID?.isEmpty == false || email?.isEmpty == false else { return nil }
        let key = [providerID, accountID ?? "", email ?? "", orgID ?? "", projectID ?? ""]
            .joined(separator: "\0")
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
