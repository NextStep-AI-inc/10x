import Foundation
import OmpKit

/// Maps `omp usage --json` output (`OmpUsageSnapshot`) into the per-account
/// summaries and usage windows the account-routing UI consumes. This is a
/// pure read: it works against stock OMP with no extension involved.
///
/// Every report whose `metadata` carries neither an `accountId` nor an
/// `email` has no stable identity and is skipped outright — see
/// `ProviderAccountRef.make`. Task 5's write path reuses `accountRef(for:)`.
enum ProviderAccountUsageBackend {
    static func accounts(from snapshot: OmpUsageSnapshot, providerID: String) -> [ProviderAccountSummary] {
        let providerReports = snapshot.reports.filter { $0.provider == providerID }
        // Enumerate before compactMap: connectionOrder is the report's index
        // within the provider's reports, so a skipped (nil-ref) report still
        // consumes its slot rather than letting later reports shift down.
        return providerReports.enumerated().compactMap { connectionOrder, report -> ProviderAccountSummary? in
            guard let ref = accountRef(for: report) else { return nil }
            let metadata = report.metadata
            let email = nonEmptyString(metadata?["email"])
            let accountID = nonEmptyString(metadata?["accountId"])
            // `accountRef(for:)` already guarantees one of these is present
            // (it derives from the same two fields), so this never actually
            // returns nil — but that invariant isn't visible to the compiler
            // across the function boundary, and a real, if unreachable, skip
            // beats fabricating a providerID-as-label placeholder.
            guard let displayLabel = email ?? accountID else { return nil }
            let orgName = nonEmptyString(metadata?["orgName"])
            let planType = nonEmptyString(metadata?["planType"])
            return ProviderAccountSummary(
                providerID: providerID,
                accountRef: ref,
                displayLabel: displayLabel,
                detailLabel: orgName ?? planType,
                connectionOrder: connectionOrder,
                availability: availability(
                    providerID: providerID,
                    accountID: accountID,
                    ref: ref,
                    snapshot: snapshot),
                isActiveForSession: nil)
        }
    }

    static func usage(from snapshot: OmpUsageSnapshot, providerID: String) -> [ProviderAccountUsage] {
        let providerReports = snapshot.reports.filter { $0.provider == providerID }
        return providerReports.compactMap { report -> ProviderAccountUsage? in
            guard let ref = accountRef(for: report) else { return nil }
            let windows = report.limits.enumerated().map { sourceIndex, limit in
                ProviderAccountUsageWindow(
                    id: limit.id,
                    label: limit.label,
                    sourceIndex: sourceIndex,
                    remainingFraction: ProviderUsagePresentation.remainingFraction(limit.amount),
                    resetsAt: limit.window?.resetsAt.map(date(fromMilliseconds:)),
                    status: limit.status)
            }
            return ProviderAccountUsage(
                providerID: providerID,
                accountRef: ref,
                refreshedAt: date(fromMilliseconds: report.fetchedAt),
                usageWindows: windows)
        }
    }

    /// The per-report account identity. Shared by `accounts(from:providerID:)`
    /// and `usage(from:providerID:)` above, and reused by Task 5's write path.
    static func accountRef(for report: OmpUsageReport) -> String? {
        ProviderAccountRef.make(
            providerID: report.provider,
            accountID: nonEmptyString(report.metadata?["accountId"]),
            email: nonEmptyString(report.metadata?["email"]),
            orgID: nonEmptyString(report.metadata?["orgId"]),
            projectID: nonEmptyString(report.metadata?["projectId"]))
    }

    private static func availability(
        providerID: String,
        accountID: String?,
        ref: String,
        snapshot: OmpUsageSnapshot
    ) -> ProviderAccountAvailability {
        if let accountID,
           snapshot.disabledCredentials.contains(where: {
               $0.provider == providerID && $0.accountId == accountID
           }) {
            return .unavailable
        }
        if snapshot.accountsWithoutUsage.contains(where: { identity in
            identityMatches(identity, providerID: providerID, ref: ref)
        }) {
            return .limited
        }
        return .available
    }

    private static func identityMatches(
        _ identity: OmpUsageAccountIdentity,
        providerID: String,
        ref: String
    ) -> Bool {
        guard identity.provider == providerID else { return false }
        return ProviderAccountRef.make(
            providerID: identity.provider,
            accountID: nonEmptyString(identity.accountId),
            email: nonEmptyString(identity.email),
            orgID: nonEmptyString(identity.orgId),
            projectID: nonEmptyString(identity.projectId)) == ref
    }

    private static func nonEmptyString(_ value: JSONValue?) -> String? {
        nonEmptyString(value?.stringValue)
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}
