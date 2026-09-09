import Foundation

struct TranscriptNavigationRequest: Equatable, Sendable {
    let rowID: String
    let nonce: UUID

    init(rowID: String, nonce: UUID = UUID()) {
        self.rowID = rowID
        self.nonce = nonce
    }
}
