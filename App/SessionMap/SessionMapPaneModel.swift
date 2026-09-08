import Observation
import SwiftUI

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
    var paneWidth: CGFloat
    var isVisible: Bool

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

    func regenerate(_ scope: SessionMapGenerationScope) { onRegenerate(scope) }
    func caughtUp() { onCaughtUp() }
    func close() {
        isVisible = false
        onClose()
    }
    func openSettings() { onOpenSettings() }
    func perform(_ action: SessionMapAction) { onAction(action) }
}
