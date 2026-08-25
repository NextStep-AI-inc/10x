import Foundation
import OmpKit

struct OmpUsageSnapshot: Decodable, Equatable, Sendable {
    let generatedAt: Int64
    let reports: [OmpUsageReport]
    let accountsWithoutUsage: [OmpUsageAccountIdentity]
    let disabledCredentials: [OmpDisabledCredential]

    static let empty = OmpUsageSnapshot(
        generatedAt: 0,
        reports: [],
        accountsWithoutUsage: [],
        disabledCredentials: [])
}

struct OmpUsageReport: Decodable, Equatable, Sendable {
    let provider: String
    let fetchedAt: Int64
    let limits: [OmpUsageLimit]
    let metadata: [String: JSONValue]?
}

struct OmpUsageLimit: Decodable, Equatable, Sendable {
    let id: String
    let label: String
    let scope: OmpUsageScope
    let window: OmpUsageWindow?
    let amount: OmpUsageAmount
    let status: String?
    let notes: [String]?
}

struct OmpUsageScope: Decodable, Equatable, Sendable {
    let provider: String
    let accountId: String?
    let projectId: String?
    let orgId: String?
    let modelId: String?
    let tier: String?
    let windowId: String?
    let shared: Bool?
}

struct OmpUsageWindow: Decodable, Equatable, Sendable {
    let id: String
    let label: String?
    let resetsAt: Int64?
}

struct OmpUsageAmount: Decodable, Equatable, Sendable {
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let usedFraction: Double?
    let remainingFraction: Double?
    let unit: String
}

struct OmpUsageAccountIdentity: Decodable, Equatable, Sendable {
    let provider: String
    let email: String?
    let accountId: String?
    let projectId: String?
    let enterpriseUrl: String?
    let orgId: String?
    let orgName: String?
}

struct OmpDisabledCredential: Decodable, Equatable, Sendable {
    let id: Int
    let provider: String
    let type: String
    let cause: String
    let email: String?
    let accountId: String?
    let orgId: String?
    let orgName: String?
    let disabledAtMs: Int64
}
