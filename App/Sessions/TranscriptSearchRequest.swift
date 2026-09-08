import Foundation

struct TranscriptSearchRequest: Equatable, Sendable {
    let entryID: String
    let query: String
    let nonce: UUID

    init?(entryID: String?, query: String, nonce: UUID = UUID()) {
        guard let entryID, !entryID.isEmpty else { return nil }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        self.entryID = entryID
        self.query = query
        self.nonce = nonce
    }
}
