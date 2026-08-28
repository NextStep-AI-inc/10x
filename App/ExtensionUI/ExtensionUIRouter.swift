import Foundation
import OmpKit

struct ExtensionUIRouter {
    /// Title of the `tenx.provider-accounts.v1` machine command channel
    /// (`ProviderAccountExtensionChannel`, `App/Providers/ProviderAccountExtensionBackend.swift`).
    /// The extension answers this channel via `method: "input"` requests
    /// carrying this exact string as their dialog `title`, but the channel
    /// is not user-facing — it is a request/reply loop between 10x and the
    /// bundled extension. `parse` below excludes it so it can never become
    /// a sheet, an inline request, or any other UI surface. Shared wire
    /// contract with `OmpExtension/src/command-channel.ts`'s
    /// `CHANNEL_MARKER`; defined once here rather than as a literal
    /// repeated at each comparison site.
    static let providerAccountChannelTitle = "tenx.provider-accounts.v1"

    private(set) var inlineRequests: [ExtensionUIState] = []
    private(set) var sheetRequest: ExtensionUIState?
    private(set) var notifications: [ExtensionUIState] = []
    private(set) var status: [String: String] = [:]
    private(set) var widgets: [String: ExtensionUIState] = [:]
    private(set) var sessionTitle: String?
    private(set) var editorText: String?
    private(set) var openURLRequest: ExtensionUIState?

    mutating func consume(_ request: ExtensionUIRequest) {
        guard let state = Self.parse(request) else { return }
        switch state {
        case .confirm, .select:
            replaceOrAppend(state, in: &inlineRequests)
        case .input, .editor:
            sheetRequest = state
        case .cancel(_, let targetID):
            inlineRequests.removeAll { $0.id == targetID }
            if sheetRequest?.id == targetID { sheetRequest = nil }
        case .notification:
            notifications.append(state)
        case .status(_, let key, let text):
            if let text { status[key] = text } else { status.removeValue(forKey: key) }
        case .widget(_, let key, let lines, _):
            if lines == nil { widgets.removeValue(forKey: key) } else { widgets[key] = state }
        case .title(_, let title):
            sessionTitle = title
        case .setEditorText(_, let text):
            editorText = text
        case .openURL:
            openURLRequest = state
        }
    }

    mutating func removeRequest(id: String) {
        inlineRequests.removeAll { $0.id == id }
        if sheetRequest?.id == id { sheetRequest = nil }
        if openURLRequest?.id == id { openURLRequest = nil }
    }

    mutating func clearEditorText() {
        editorText = nil
    }

    static func parse(_ request: ExtensionUIRequest) -> ExtensionUIState? {
        let payload = request.payload
        // Reserved machine-channel marker: never surface it as UI. Scoped
        // away from "setTitle" deliberately — that method's own `title`
        // field means the session's display name, a different concept
        // that happens to share the same JSON key, and must not be
        // dropped on a coincidental string match.
        if request.method != "setTitle",
           payload["title"]?.stringValue == Self.providerAccountChannelTitle {
            return nil
        }
        switch request.method {
        case "confirm":
            guard let title = payload["title"]?.stringValue,
                  let message = payload["message"]?.stringValue else { return nil }
            return .confirm(
                id: request.id, title: title, message: message,
                timeout: payload["timeout"]?.intValue)
        case "select":
            guard let title = payload["title"]?.stringValue,
                  let labels = payload["options"]?.arrayValue?.compactMap(\.stringValue)
            else { return nil }
            let details = payload["optionDetails"]?.arrayValue ?? []
            let options = labels.enumerated().map { index, label in
                ExtensionSelectOption(
                    label: label,
                    detail: details.indices.contains(index)
                        ? details[index]["description"]?.stringValue
                        : nil)
            }
            return .select(
                id: request.id, title: title, options: options,
                timeout: payload["timeout"]?.intValue)
        case "input":
            guard let title = payload["title"]?.stringValue else { return nil }
            return .input(
                id: request.id, title: title,
                placeholder: payload["placeholder"]?.stringValue,
                timeout: payload["timeout"]?.intValue)
        case "editor":
            guard let title = payload["title"]?.stringValue else { return nil }
            return .editor(
                id: request.id, title: title,
                prefill: payload["prefill"]?.stringValue,
                promptStyle: payload["promptStyle"]?.boolValue == true)
        case "cancel":
            guard let targetID = payload["targetId"]?.stringValue else { return nil }
            return .cancel(id: request.id, targetID: targetID)
        case "notify":
            guard let message = payload["message"]?.stringValue else { return nil }
            return .notification(
                id: request.id, message: message,
                level: payload["notifyType"]?.stringValue ?? "info")
        case "setStatus":
            guard let key = payload["statusKey"]?.stringValue else { return nil }
            return .status(id: request.id, key: key, text: payload["statusText"]?.stringValue)
        case "setWidget":
            guard let key = payload["widgetKey"]?.stringValue else { return nil }
            return .widget(
                id: request.id, key: key,
                lines: payload["widgetLines"]?.arrayValue?.compactMap(\.stringValue),
                placement: payload["widgetPlacement"]?.stringValue)
        case "setTitle":
            guard let title = payload["title"]?.stringValue else { return nil }
            return .title(id: request.id, title: title)
        case "set_editor_text":
            guard let text = payload["text"]?.stringValue else { return nil }
            return .setEditorText(id: request.id, text: text)
        case "open_url":
            guard let target = validatedURL(payload["launchUrl"]?.stringValue)
                    ?? validatedURL(payload["url"]?.stringValue)
            else { return nil }
            return .openURL(
                id: request.id, target: target,
                instructions: payload["instructions"]?.stringValue)
        default:
            return nil
        }
    }

    private static func validatedURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        return url
    }

    private func replaceOrAppend(_ state: ExtensionUIState, in requests: inout [ExtensionUIState]) {
        if let index = requests.firstIndex(where: { $0.id == state.id }) {
            requests[index] = state
        } else {
            requests.append(state)
        }
    }
}
