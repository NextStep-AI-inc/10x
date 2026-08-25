import Foundation
import OmpKit

struct ExtensionSelectOption: Equatable {
    let label: String
    let detail: String?
}

enum ExtensionUIState: Identifiable, Equatable {
    case confirm(id: String, title: String, message: String, timeout: Int?)
    case select(id: String, title: String, options: [ExtensionSelectOption], timeout: Int?)
    case input(id: String, title: String, placeholder: String?, timeout: Int?)
    case editor(id: String, title: String, prefill: String?, promptStyle: Bool)
    case cancel(id: String, targetID: String)
    case notification(id: String, message: String, level: String)
    case status(id: String, key: String, text: String?)
    case widget(id: String, key: String, lines: [String]?, placement: String?)
    case title(id: String, title: String)
    case setEditorText(id: String, text: String)
    case openURL(id: String, target: URL, instructions: String?)

    var id: String {
        switch self {
        case .confirm(let id, _, _, _),
             .select(let id, _, _, _),
             .input(let id, _, _, _),
             .editor(let id, _, _, _),
             .cancel(let id, _),
             .notification(let id, _, _),
             .status(let id, _, _),
             .widget(let id, _, _, _),
             .title(let id, _),
             .setEditorText(let id, _),
             .openURL(let id, _, _):
            return id
        }
    }
}

enum ExtensionUIResponse: Equatable {
    case confirmed(Bool)
    case value(String)
    case cancelled(timedOut: Bool)

    var body: [String: JSONValue] {
        switch self {
        case .confirmed(let confirmed):
            return ["confirmed": .bool(confirmed)]
        case .value(let value):
            return ["value": .string(value)]
        case .cancelled(let timedOut):
            var body: [String: JSONValue] = ["cancelled": .bool(true)]
            if timedOut { body["timedOut"] = .bool(true) }
            return body
        }
    }
}
