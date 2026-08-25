import Foundation
import OmpKit

enum TranscriptItem: Identifiable, Equatable {
    case threadStart(id: String, date: Date?)
    case message(TranscriptMessage)
    case annotation(TranscriptAnnotation)
    case notice(id: String, level: String, message: String)
    case tool(ToolPresentation)
    case extensionUI(ExtensionUIState)
    case rawEvent(id: String, type: String, payload: JSONValue)

    var id: String {
        switch self {
        case .threadStart(let id, _),
             .notice(let id, _, _),
             .rawEvent(let id, _, _):
            return id
        case .message(let message):
            return message.id
        case .annotation(let annotation):
            return annotation.id
        case .tool(let presentation):
            return presentation.id
        case .extensionUI(let state):
            return state.id
        }
    }
}
