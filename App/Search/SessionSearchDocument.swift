import Foundation

struct SessionSearchFingerprint: Equatable, Sendable {
    let path: String
    let modified: TimeInterval
    let sizeBytes: Int
}

struct SessionSearchDocument: Equatable, Sendable {
    let sessionPath: String
    let entryID: String?
    let projectPath: String
    let title: String
    let excerpt: String
    let kind: SearchResultKind
    let sessionModified: TimeInterval
    let entryOrder: Int
    let normalizedText: String
}
