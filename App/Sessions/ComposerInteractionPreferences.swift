import Foundation
import Observation

enum ComposerSendAction: String, CaseIterable {
    case steer
    case followUp

    var title: String {
        switch self {
        case .steer: "Steer"
        case .followUp: "Follow up"
        }
    }
}

enum ComposerReturnAction: String, CaseIterable {
    case primary
    case alternate
    case newline
}

enum ComposerReturnShortcut: String, CaseIterable, Identifiable {
    case enter
    case commandEnter
    case shiftEnter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enter: "Enter"
        case .commandEnter: "Command-Enter"
        case .shiftEnter: "Shift-Enter"
        }
    }
}

@MainActor
@Observable
final class ComposerInteractionPreferences {
    static let shared = ComposerInteractionPreferences()

    var defaultSendAction: ComposerSendAction {
        didSet { defaults.set(defaultSendAction.rawValue, forKey: defaultSendActionKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyPrefix: String
    private var returnActions: [ComposerReturnShortcut: ComposerReturnAction]

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "composer-interaction"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        defaultSendAction = ComposerSendAction(
            rawValue: defaults.string(forKey: "\(keyPrefix).default-send-action") ?? "") ?? .steer

        let saved = Dictionary(uniqueKeysWithValues: ComposerReturnShortcut.allCases.map { shortcut in
            let rawValue = defaults.string(forKey: "\(keyPrefix).shortcut.\(shortcut.rawValue)") ?? ""
            return (shortcut, ComposerReturnAction(rawValue: rawValue))
        })
        let savedActions = saved.values.compactMap { $0 }
        if savedActions.count == ComposerReturnAction.allCases.count,
           Set(savedActions).count == ComposerReturnAction.allCases.count {
            returnActions = saved.compactMapValues { $0 }
        } else {
            returnActions = Self.defaultReturnActions
        }
    }

    func action(for shortcut: ComposerReturnShortcut) -> ComposerReturnAction {
        if let action = returnActions[shortcut] { return action }
        switch shortcut {
        case .enter: return .primary
        case .commandEnter: return .alternate
        case .shiftEnter: return .newline
        }
    }

    func assign(_ action: ComposerReturnAction, to shortcut: ComposerReturnShortcut) {
        let displacedAction = self.action(for: shortcut)
        guard displacedAction != action else { return }
        guard let priorShortcut = ComposerReturnShortcut.allCases.first(where: {
            self.action(for: $0) == action
        }) else { return }

        returnActions[shortcut] = action
        returnActions[priorShortcut] = displacedAction
        persistReturnActions()
    }

    func title(for action: ComposerReturnAction) -> String {
        switch action {
        case .primary:
            defaultSendAction.title
        case .alternate:
            defaultSendAction == .steer
                ? ComposerSendAction.followUp.title
                : ComposerSendAction.steer.title
        case .newline:
            "New line"
        }
    }

    private var defaultSendActionKey: String { "\(keyPrefix).default-send-action" }

    private func persistReturnActions() {
        for shortcut in ComposerReturnShortcut.allCases {
            defaults.set(action(for: shortcut).rawValue, forKey: "\(keyPrefix).shortcut.\(shortcut.rawValue)")
        }
    }

    private static let defaultReturnActions: [ComposerReturnShortcut: ComposerReturnAction] = [
        .enter: .primary,
        .commandEnter: .alternate,
        .shiftEnter: .newline,
    ]
}
