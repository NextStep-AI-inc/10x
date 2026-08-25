import OmpKit

enum TranscriptItem: Identifiable, Equatable {
    case message(id: String, message: JSONValue, isFinal: Bool)
    case notice(id: String, level: String, message: String)
    case rawEvent(id: String, type: String, payload: JSONValue)

    var id: String {
        switch self {
        case .message(let id, _, _),
             .notice(let id, _, _),
             .rawEvent(let id, _, _):
            return id
        }
    }
}
