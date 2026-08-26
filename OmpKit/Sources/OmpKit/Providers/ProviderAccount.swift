import Foundation

public enum ProviderAccountAvailability: String, Sendable, Equatable, Decodable {
    case available
    case limited
    case unavailable

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ProviderAccountAvailability(rawValue: value) ?? .unavailable
    }
}

public struct ProviderAccountSummary: Sendable, Equatable, Decodable, Identifiable {
    public let providerID: String
    public let accountRef: String
    public let displayLabel: String
    public let detailLabel: String?
    public let connectionOrder: Int
    public let availability: ProviderAccountAvailability
    public let isActiveForSession: Bool?
    public var id: String { "\(providerID):\(accountRef)" }

    public init(
        providerID: String,
        accountRef: String,
        displayLabel: String,
        detailLabel: String? = nil,
        connectionOrder: Int,
        availability: ProviderAccountAvailability,
        isActiveForSession: Bool? = nil
    ) {
        self.providerID = providerID
        self.accountRef = accountRef
        self.displayLabel = displayLabel
        self.detailLabel = detailLabel
        self.connectionOrder = connectionOrder
        self.availability = availability
        self.isActiveForSession = isActiveForSession
    }

    private enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case accountRef
        case displayLabel
        case detailLabel
        case connectionOrder
        case availability
        case isActiveForSession
    }
}

public struct ProviderAccountUsageWindow: Sendable, Equatable, Decodable {
    public struct Duration: Sendable, Equatable, Decodable {
        public enum Unit: Sendable, Equatable, Decodable {
            case minute
            case hour
            case day
            case week
            case month
            case year
            case unknown(String)

            public init(from decoder: any Decoder) throws {
                let value = try decoder.singleValueContainer().decode(String.self)
                switch value {
                case "minute": self = .minute
                case "hour": self = .hour
                case "day": self = .day
                case "week": self = .week
                case "month": self = .month
                case "year": self = .year
                default: self = .unknown(value)
                }
            }
        }

        public let value: Int
        public let unit: Unit

        public init(value: Int, unit: Unit) {
            self.value = value
            self.unit = unit
        }
    }

    public let id: String
    public let label: String
    public let duration: Duration?
    public let sourceIndex: Int
    public let remainingFraction: Double?
    public let resetsAt: Date?
    public let status: String?

    public init(
        id: String,
        label: String,
        duration: Duration? = nil,
        sourceIndex: Int,
        remainingFraction: Double? = nil,
        resetsAt: Date? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.label = label
        self.duration = duration
        self.sourceIndex = sourceIndex
        self.remainingFraction = remainingFraction
        self.resetsAt = resetsAt
        self.status = status
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            label: try container.decode(String.self, forKey: .label),
            duration: try container.decodeIfPresent(Duration.self, forKey: .duration),
            sourceIndex: try container.decode(Int.self, forKey: .sourceIndex),
            remainingFraction: try container.decodeIfPresent(Double.self, forKey: .remainingFraction),
            resetsAt: try container.decodeISO8601DateIfPresent(forKey: .resetsAt),
            status: try container.decodeIfPresent(String.self, forKey: .status)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case duration
        case sourceIndex
        case remainingFraction
        case resetsAt
        case status
    }
}

public struct ProviderAccountUsage: Sendable, Equatable, Decodable {
    public let providerID: String
    public let accountRef: String
    public let refreshedAt: Date
    public let usageWindows: [ProviderAccountUsageWindow]

    public init(
        providerID: String,
        accountRef: String,
        refreshedAt: Date,
        usageWindows: [ProviderAccountUsageWindow]
    ) {
        self.providerID = providerID
        self.accountRef = accountRef
        self.refreshedAt = refreshedAt
        self.usageWindows = usageWindows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            providerID: try container.decode(String.self, forKey: .providerID),
            accountRef: try container.decode(String.self, forKey: .accountRef),
            refreshedAt: try container.decodeISO8601Date(forKey: .refreshedAt),
            usageWindows: try container.decode([ProviderAccountUsageWindow].self, forKey: .usageWindows)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case accountRef
        case refreshedAt
        case usageWindows
    }
}

public enum ProviderAccountChangeReason: Sendable, Equatable, Decodable {
    case manual
    case automaticFailover
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value)
    }

    init(rawValue: String) {
        switch rawValue {
        case "manual": self = .manual
        case "automaticFailover": self = .automaticFailover
        default: self = .unknown(rawValue)
        }
    }
}

public struct ProviderAccountChangedEvent: Sendable, Equatable, Decodable {
    public let providerID: String
    public let accountRef: String
    public let reason: ProviderAccountChangeReason
    public let sequence: Int

    public init(
        providerID: String,
        accountRef: String,
        reason: ProviderAccountChangeReason,
        sequence: Int
    ) {
        self.providerID = providerID
        self.accountRef = accountRef
        self.reason = reason
        self.sequence = sequence
    }

    init(object: [String: JSONValue]) throws {
        guard let providerID = object["providerId"]?.stringValue else {
            throw RpcFrameError.malformedFrame(
                type: "provider_account_changed", underlying: "missing providerId")
        }
        guard let accountRef = object["accountRef"]?.stringValue else {
            throw RpcFrameError.malformedFrame(
                type: "provider_account_changed", underlying: "missing accountRef")
        }
        guard let reason = object["reason"]?.stringValue else {
            throw RpcFrameError.malformedFrame(
                type: "provider_account_changed", underlying: "missing reason")
        }
        guard let sequence = object["sequence"]?.intValue else {
            throw RpcFrameError.malformedFrame(
                type: "provider_account_changed", underlying: "missing sequence")
        }
        self.init(
            providerID: providerID,
            accountRef: accountRef,
            reason: ProviderAccountChangeReason(rawValue: reason),
            sequence: sequence
        )
    }

    private enum CodingKeys: String, CodingKey {
        case providerID = "providerId"
        case accountRef
        case reason
        case sequence
    }
}

private extension KeyedDecodingContainer {
    func decodeISO8601Date(forKey key: Key) throws -> Date {
        let value = try decode(String.self, forKey: key)
        if let date = iso8601Date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Expected ISO-8601 date string")
    }

    func decodeISO8601DateIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeISO8601Date(forKey: key)
    }
}

private func iso8601Date(from value: String) -> Date? {
    for options in [
        ISO8601DateFormatter.Options.withInternetDateTime.union(.withFractionalSeconds),
        .withInternetDateTime,
    ] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        if let date = formatter.date(from: value) {
            return date
        }
    }
    return nil
}
