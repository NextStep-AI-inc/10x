import Foundation
import OmpKit

struct ProviderUsagePresentation: Equatable, Sendable {
    let providers: [ProviderUsageProvider]
    let accountsWithoutUsage: [ProviderUsageAccount]
    let credentialIssues: [ProviderCredentialIssue]

    static let empty = ProviderUsagePresentation(
        providers: [],
        accountsWithoutUsage: [],
        credentialIssues: [])

    var dockProviders: [ProviderUsageProvider] {
        providers.compactMap { provider in
            let accounts: [ProviderUsageAccount] = provider.accounts.compactMap { account in
                let limits = account.limits.filter { $0.hasComputablePercentage }
                guard !limits.isEmpty else { return nil }
                return ProviderUsageAccount(
                    id: account.id,
                    label: account.label,
                    identity: account.identity,
                    limits: limits,
                    amounts: [],
                    notes: [],
                    isUsageAvailable: true)
            }
            guard !accounts.isEmpty else { return nil }
            return ProviderUsageProvider(id: provider.id, name: provider.name, accounts: accounts)
        }
    }

    static func make(
        snapshot: OmpUsageSnapshot,
        providerNames: [String: String],
        now: Date
    ) -> ProviderUsagePresentation {
        var providerOrder: [String] = []
        var accountsByProvider: [String: [ProviderUsageAccount]] = [:]
        var nextSourceIndexByProvider: [String: Int] = [:]

        for report in snapshot.reports {
            if accountsByProvider[report.provider] == nil {
                providerOrder.append(report.provider)
                accountsByProvider[report.provider] = []
            }
            let sourceIndexOffset = nextSourceIndexByProvider[report.provider, default: 0]
            accountsByProvider[report.provider, default: []].append(
                account(from: report, now: now, sourceIndexOffset: sourceIndexOffset))
            nextSourceIndexByProvider[report.provider] = sourceIndexOffset + report.limits.count
        }

        let providers = providerOrder.map { providerID in
            ProviderUsageProvider(
                id: providerID,
                name: providerNames[providerID] ?? providerID,
                accounts: accountsByProvider[providerID] ?? [])
        }
        let missingAccounts = snapshot.accountsWithoutUsage.map { identity in
            unavailableAccount(from: identity)
        }
        let credentialIssues = snapshot.disabledCredentials.map { credential in
            ProviderCredentialIssue(
                id: "\(credential.provider):\(credential.id)",
                providerID: credential.provider,
                providerName: providerNames[credential.provider] ?? credential.provider,
                label: accountLabel(
                    email: credential.email,
                    accountID: credential.accountId,
                    projectID: nil,
                    enterpriseURL: nil,
                    orgID: credential.orgId,
                    orgName: credential.orgName),
                type: credential.type,
                disabledAt: date(fromMilliseconds: credential.disabledAtMs))
        }
        return ProviderUsagePresentation(
            providers: providers,
            accountsWithoutUsage: missingAccounts,
            credentialIssues: credentialIssues)
    }

    private static func account(
        from report: OmpUsageReport,
        now: Date,
        sourceIndexOffset: Int
    ) -> ProviderUsageAccount {
        let scope = report.limits.first?.scope
        let identity = ProviderUsageAccountIdentity(
            email: report.metadata?["email"]?.stringValue,
            accountID: report.metadata?["accountId"]?.stringValue ?? scope?.accountId,
            projectID: report.metadata?["projectId"]?.stringValue ?? scope?.projectId,
            enterpriseURL: report.metadata?["enterpriseUrl"]?.stringValue,
            orgID: report.metadata?["orgId"]?.stringValue ?? scope?.orgId,
            orgName: report.metadata?["orgName"]?.stringValue)
        let limits: [ProviderUsageLimit] = report.limits.enumerated().compactMap { offset, limit in
            guard let fraction = Self.remainingFraction(limit.amount) else { return nil }
            return ProviderUsageLimit(
                id: limit.id,
                label: limit.label,
                percentage: Int((fraction * 100).rounded()),
                detailReset: Self.detailResetText(window: limit.window),
                railReset: Self.railResetText(window: limit.window, now: now),
                windowDurationRank: Self.windowDurationRank(for: limit),
                sourceIndex: sourceIndexOffset + offset)
        }
        let amounts: [ProviderUsageAmount] = report.limits.compactMap { limit in
            guard Self.remainingFraction(limit.amount) == nil, let used = limit.amount.used else { return nil }
            return ProviderUsageAmount(id: limit.id, label: limit.label, value: used, unit: limit.amount.unit)
        }
        return ProviderUsageAccount(
            id: accountID(providerID: report.provider, identity: identity, limits: report.limits),
            label: accountLabel(
                email: identity.email,
                accountID: identity.accountID,
                projectID: identity.projectID,
                enterpriseURL: identity.enterpriseURL,
                orgID: identity.orgID,
                orgName: identity.orgName),
            identity: identity,
            limits: limits,
            amounts: amounts,
            notes: report.limits.flatMap { $0.notes ?? [] },
            isUsageAvailable: true)
    }

    private static func unavailableAccount(from identity: OmpUsageAccountIdentity) -> ProviderUsageAccount {
        let presentationIdentity = ProviderUsageAccountIdentity(
            email: identity.email,
            accountID: identity.accountId,
            projectID: identity.projectId,
            enterpriseURL: identity.enterpriseUrl,
            orgID: identity.orgId,
            orgName: identity.orgName)
        return ProviderUsageAccount(
            id: accountID(providerID: identity.provider, identity: presentationIdentity, limits: []),
            label: accountLabel(
                email: identity.email,
                accountID: identity.accountId,
                projectID: identity.projectId,
                enterpriseURL: identity.enterpriseUrl,
                orgID: identity.orgId,
                orgName: identity.orgName),
            identity: presentationIdentity,
            limits: [],
            amounts: [],
            notes: [],
            isUsageAvailable: false)
    }

    static func remainingFraction(_ amount: OmpUsageAmount) -> Double? {
        if let remaining = amount.remainingFraction { return clamp(remaining) }
        if let used = amount.usedFraction { return clamp(1 - used) }
        if let used = amount.used, let limit = amount.limit, limit > 0 {
            return clamp(1 - used / limit)
        }
        if amount.unit == "percent", let used = amount.used {
            return clamp(1 - used / 100)
        }
        return nil
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static let knownWindowDurationRanks = [
        "hourly": 60,
        "1-hour": 60,
        "five-hour": 300,
        "5-hour": 300,
        "5 hour": 300,
        "daily": 1_440,
        "day": 1_440,
        "weekly": 10_080,
        "week": 10_080,
        "monthly": 43_200,
        "month": 43_200,
        "annual": 525_600,
        "yearly": 525_600,
        "year": 525_600,
    ]

    private static func windowDurationRank(for limit: OmpUsageLimit) -> Int? {
        [limit.window?.id, limit.window?.label, limit.scope.windowId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .compactMap { knownWindowDurationRanks[$0] }
            .first
    }

    private static func accountID(
        providerID: String,
        identity: ProviderUsageAccountIdentity,
        limits: [OmpUsageLimit]
    ) -> String {
        let identityValues: [String] = [
            identity.email,
            identity.accountID,
            identity.projectID,
            identity.enterpriseURL,
            identity.orgID,
            identity.orgName,
        ].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "\(value.utf8.count):\(value)"
        }
        let discriminator = identityValues.isEmpty
            ? limits.first?.id ?? "connected-account"
            : identityValues.joined(separator: "|")
        return "\(providerID):\(discriminator)"
    }

    private static func accountLabel(
        email: String?,
        accountID: String?,
        projectID: String?,
        enterpriseURL: String?,
        orgID: String?,
        orgName: String?
    ) -> String {
        let primary = email ?? accountID ?? projectID
        let organization = orgName ?? orgID ?? enterpriseURL
        switch (primary, organization) {
        case let (primary?, organization?):
            return "\(primary) (\(organization))"
        case let (primary?, nil):
            return primary
        case let (nil, organization?):
            return organization
        case (nil, nil):
            return "Connected account"
        }
    }

    private static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    private static func detailResetText(window: OmpUsageWindow?) -> String? {
        guard let window else { return nil }
        guard let resetsAt = window.resetsAt else { return window.label }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date(fromMilliseconds: resetsAt))
    }

    private static func railResetText(window: OmpUsageWindow?, now: Date) -> String {
        guard let resetsAt = window?.resetsAt else { return window?.label ?? "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date(fromMilliseconds: resetsAt), relativeTo: now)
    }
}

struct ProviderUsageProvider: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let accounts: [ProviderUsageAccount]

    var limits: [ProviderUsageLimit] {
        accounts.flatMap(\.limits)
    }

    var ringLimits: [ProviderUsageLimit] {
        let flattenedLimits = limits
        let orderedKnownLimits = flattenedLimits.enumerated()
            .filter { $0.element.windowDurationRank != nil }
            .sorted { lhs, rhs in
                guard let lhsRank = lhs.element.windowDurationRank,
                      let rhsRank = rhs.element.windowDurationRank
                else {
                    return lhs.offset < rhs.offset
                }
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.element.sourceIndex != rhs.element.sourceIndex {
                    return lhs.element.sourceIndex < rhs.element.sourceIndex
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        var knownIndex = 0

        return flattenedLimits.map { limit in
            guard limit.windowDurationRank != nil else { return limit }
            defer { knownIndex += 1 }
            return orderedKnownLimits[knownIndex]
        }
    }

    var abbreviation: String {
        Self.knownAbbreviations[id] ?? Self.fallbackAbbreviation(name: name, id: id)
    }

    private static let knownAbbreviations = [
        "anthropic": "ANT",
        "openai-codex": "OAI",
        "cursor": "CUR",
        "google-gemini-cli": "GCA",
        "github-copilot": "GHC",
    ]

    private static func fallbackAbbreviation(name: String, id: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var characters: [Character]

        switch words.count {
        case 3...:
            characters = words.prefix(3).compactMap(\.first)
        case 2:
            characters = Array(words[0].prefix(2)) + Array(words[1].prefix(1))
        case 1:
            characters = Array(words[0].prefix(3))
        default:
            characters = []
        }

        if characters.count < 3 {
            characters.append(contentsOf: id.uppercased().filter { $0.isLetter || $0.isNumber })
        }
        var normalizedCharacters = String(characters).uppercased().filter { $0.isLetter || $0.isNumber }
        while normalizedCharacters.count < 3 {
            normalizedCharacters.append("X")
        }
        return String(normalizedCharacters.prefix(3))
    }
}

struct ProviderUsageAccount: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let identity: ProviderUsageAccountIdentity
    let limits: [ProviderUsageLimit]
    let amounts: [ProviderUsageAmount]
    let notes: [String]
    let isUsageAvailable: Bool
}

struct ProviderUsageAccountIdentity: Equatable, Sendable {
    let email: String?
    let accountID: String?
    let projectID: String?
    let enterpriseURL: String?
    let orgID: String?
    let orgName: String?
}

struct ProviderUsageLimit: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case standard
        case warning
        case exhausted
    }

    let id: String
    let label: String
    let percentage: Int
    let detailReset: String?
    let railReset: String
    let windowDurationRank: Int?
    let sourceIndex: Int

    init(id: String, label: String, percentage: Int, resetWindow: String) {
        self.init(id: id, label: label, percentage: percentage, detailReset: resetWindow, railReset: resetWindow)
    }

    init(
        id: String,
        label: String,
        percentage: Int,
        detailReset: String?,
        railReset: String,
        windowDurationRank: Int? = nil,
        sourceIndex: Int = 0
    ) {
        self.id = id
        self.label = label
        self.percentage = percentage
        self.detailReset = detailReset
        self.railReset = railReset
        self.windowDurationRank = windowDurationRank
        self.sourceIndex = sourceIndex
    }

    var resetWindow: String { railReset }
    var hasComputablePercentage: Bool { true }

    var normalizedFraction: Double {
        Double(min(max(percentage, 0), 100)) / 100
    }

    var tone: Tone {
        if percentage <= 0 { return .exhausted }
        if percentage <= 20 { return .warning }
        return .standard
    }

    static func remainingPercentage(usedFraction: Double) -> Int {
        Int((min(max(1 - usedFraction, 0), 1) * 100).rounded())
    }
}

struct ProviderUsageAmount: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: Double
    let unit: String
}

struct ProviderCredentialIssue: Identifiable, Equatable, Sendable {
    let id: String
    let providerID: String
    let providerName: String
    let label: String
    let type: String
    let disabledAt: Date
}
