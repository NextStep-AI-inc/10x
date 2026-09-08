import Observation
import SwiftUI

private struct SessionMapReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var sessionMapReduceMotionOverride: Bool? {
        get { self[SessionMapReduceMotionOverrideKey.self] }
        set { self[SessionMapReduceMotionOverrideKey.self] = newValue }
    }
}

enum SessionMapPanePresentation: Equatable, Sendable {
    case docked(width: CGFloat)
    case drawer(width: CGFloat)

    static func resolve(
        windowWidth: CGFloat,
        requestedPaneWidth: CGFloat
    ) -> SessionMapPanePresentation {
        let minimumWidth: CGFloat = 320
        let defaultWidth: CGFloat = 440
        if windowWidth < 1_180 {
            let maximumDrawerWidth = max(defaultWidth, windowWidth / 2)
            return .drawer(width: min(max(requestedPaneWidth, minimumWidth), maximumDrawerWidth))
        }
        return .docked(width: min(max(requestedPaneWidth, minimumWidth), windowWidth / 2))
    }

    var width: CGFloat {
        switch self {
        case .docked(let width), .drawer(let width): width
        }
    }
}

enum SessionMapPaneState: Equatable, Sendable {
    case empty
    case needsGeneration
    case writing
    case ready
    case checking
    case stale
    case failed(message: String)
    case needsModel
}

enum SessionMapGenerationScope: Equatable, Sendable {
    case sinceCaughtUp
    case recentThreeTurns
    case wholeSession
}

@MainActor
@Observable
final class SessionMapPaneModel {
    private(set) var displayedDocument: SessionMapDocument?
    private(set) var state: SessionMapPaneState
    var focus: SessionMapFocus
    private(set) var paneWidth: CGFloat
    private(set) var isVisible: Bool

    private let onRegenerate: (SessionMapGenerationScope) -> Void
    private let onCaughtUp: () -> Void
    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onAction: (SessionMapAction) -> Void

    init(
        displayedDocument: SessionMapDocument? = nil,
        state: SessionMapPaneState = .empty,
        focus: SessionMapFocus = SessionMapFocus(
            selectedNodeID: nil,
            hoveredNodeID: nil,
            focusedNodeID: nil,
            flowStepIndex: nil),
        paneWidth: CGFloat = 440,
        isVisible: Bool = false,
        onRegenerate: @escaping (SessionMapGenerationScope) -> Void = { _ in },
        onCaughtUp: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onAction: @escaping (SessionMapAction) -> Void = { _ in }
    ) {
        self.displayedDocument = displayedDocument
        self.state = state
        self.focus = focus
        self.paneWidth = paneWidth
        self.isVisible = isVisible
        self.onRegenerate = onRegenerate
        self.onCaughtUp = onCaughtUp
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onAction = onAction
    }

    func replaceDocument(_ document: SessionMapDocument, state: SessionMapPaneState = .ready) {
        if let displayedDocument {
            focus = SessionMapInteraction.reconciledFocus(
                focus, replacing: displayedDocument, with: document)
        }
        displayedDocument = document
        self.state = state
    }

    func transition(to state: SessionMapPaneState) {
        self.state = state
    }

    func synchronizePresentation(paneWidth: CGFloat, isVisible: Bool) {
        self.paneWidth = paneWidth
        self.isVisible = isVisible
    }

    func regenerate(_ scope: SessionMapGenerationScope) { onRegenerate(scope) }
    func caughtUp() { onCaughtUp() }
    func close() {
        isVisible = false
        onClose()
    }
    func openSettings() { onOpenSettings() }
    func perform(_ action: SessionMapAction) { onAction(action) }
}
