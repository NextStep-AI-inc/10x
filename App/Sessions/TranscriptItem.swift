import OmpKit

enum TranscriptItem: Identifiable, Equatable {
    case message(id: String, message: JSONValue, isFinal: Bool)
    case notice(id: String, level: String, message: String)
    case tool(ToolPresentation)
    case extensionUI(ExtensionUIState)
    case rawEvent(id: String, type: String, payload: JSONValue)

    var id: String {
        switch self {
        case .message(let id, _, _),
             .notice(let id, _, _),
             .rawEvent(let id, _, _):
            return id
        case .tool(let presentation):
            return presentation.id
        case .extensionUI(let state):
            return state.id
        }
    }
}
