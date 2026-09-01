import Foundation
import OmpKit

enum TranscriptItem: Identifiable, Equatable, Sendable {
    case threadStart(id: String, date: Date?)
    case message(TranscriptMessage)
    case annotation(TranscriptAnnotation)
    case subagent(SubagentPresentation)
    case notice(id: String, level: String, message: String)
    case tool(ToolPresentation)
    case extensionUI(ExtensionUIState)

    var id: String {
        switch self {
        case .threadStart(let id, _),
             .notice(let id, _, _):
            return id
        case .message(let message):
            return message.id
        case .annotation(let annotation):
            return annotation.id
        case .subagent(let presentation):
            return presentation.id
        case .tool(let presentation):
            return presentation.id
        case .extensionUI(let state):
            return state.id
        }
    }

    var viewID: String {
        switch self {
        case .threadStart(let id, _):
            "thread-start:\(id)"
        case .message(let message):
            "message:\(message.id)"
        case .annotation(let annotation):
            "annotation:\(annotation.id)"
        case .subagent(let presentation):
            "subagent:\(presentation.id)"
        case .notice(let id, _, _):
            "notice:\(id)"
        case .tool(let presentation):
            "tool:\(presentation.id)"
        case .extensionUI(let state):
            "extension-ui:\(state.id)"
        }
    }
}
