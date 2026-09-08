import Foundation

struct SessionMapSource: Equatable, Sendable {
    let sessionKey: String
    let lineage: String
    let entries: [SessionMapSourceEntry]
    let finishedTurnIDs: [String]
    let knownRefs: Set<String>
    let statusEvidence: [SessionMapStatusEvidence]
}

struct SessionMapSourceEntry: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case prompt
        case assistant
        case tool
        case attention
        case annotation
    }

    let id: String
    let timestamp: Date?
    let kind: Kind
    let text: String
    let primary: String?
    let outcome: String?
    let facts: [String: SessionMapFact]
    let statusEvidence: [SessionMapStatusEvidence]
    let contentFingerprint: String

    init(
        id: String,
        timestamp: Date? = nil,
        kind: Kind,
        text: String,
        primary: String? = nil,
        outcome: String? = nil,
        facts: [String: SessionMapFact] = [:],
        statusEvidence: [SessionMapStatusEvidence] = [],
        contentFingerprint: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.text = text
        self.primary = primary
        self.outcome = outcome
        self.facts = facts
        self.statusEvidence = statusEvidence
        self.contentFingerprint = contentFingerprint
    }
}

struct SessionMapCursor: Equatable, Sendable {
    let lineage: String
    let entryID: String?
}

struct SessionMapDigest: Equatable, Sendable {
    let text: String
    let hash: String
    let facts: [String: SessionMapFact]
    let knownRefs: Set<String>
    let cursor: SessionMapCursor
    let sourceFingerprintManifest: [String: String]
    let statusEvidence: [SessionMapStatusEvidence]
}
