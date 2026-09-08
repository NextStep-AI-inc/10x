import Foundation
import OmpKit

struct TranscriptSnapshot: Equatable, Sendable {
    let processorID: UUID
    let revision: UInt64
    let items: [TranscriptItem]
    let runtimeState: SessionRuntimeState
}

enum TranscriptInitialContent: Sendable {
    case history(TranscriptHistory)
    case messages([JSONValue])
}
