import Foundation

struct TranscriptAnnotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case model
        case thinking
        case mode
        case compaction
        case branch
        case retry
        case notice
    }

    enum Tone: Equatable {
        case neutral
        case interactive
        case warning
        case error
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String?
    let timestamp: Date?
    let tone: Tone
}

