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
    var activity: SessionMapActivity
    var focus: SessionMapFocus
    private(set) var paneWidth: CGFloat
    private(set) var firstSeenOrder: [String]
    private(set) var updatedAt: Date?
    private(set) var attribution: String?
    private(set) var isVisible: Bool
    private(set) var retainedFailureMessage: String?

    private let onGenerate: (SessionMapGenerationScope, Bool) -> Void
    private let onCaughtUp: () -> Void
    private let onClose: () -> Void
    private let onOpenSettings: () -> Void
    private let onAction: (SessionMapAction) -> Void

    init(
        displayedDocument: SessionMapDocument? = nil,
        state: SessionMapPaneState = .empty,
        activity: SessionMapActivity = .empty,
        focus: SessionMapFocus = SessionMapFocus(
            selectedNodeID: nil,
            hoveredNodeID: nil,
            focusedNodeID: nil,
            flowStepIndex: nil),
        paneWidth: CGFloat = 440,
        firstSeenOrder: [String] = [],
        updatedAt: Date? = nil,
        attribution: String? = nil,
        isVisible: Bool = false,
        onRegenerate: @escaping (SessionMapGenerationScope) -> Void = { _ in },
        onGenerate: ((SessionMapGenerationScope, Bool) -> Void)? = nil,
        onCaughtUp: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onAction: @escaping (SessionMapAction) -> Void = { _ in }
    ) {
        self.displayedDocument = displayedDocument
        self.state = state
        self.activity = activity
        self.focus = focus
        self.paneWidth = paneWidth
        self.firstSeenOrder = firstSeenOrder
        self.updatedAt = updatedAt
        self.attribution = attribution
        self.isVisible = isVisible
        retainedFailureMessage = nil
        self.onGenerate = onGenerate ?? { scope, _ in onRegenerate(scope) }
        self.onCaughtUp = onCaughtUp
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
        self.onAction = onAction
    }

    func replaceDocument(
        _ document: SessionMapDocument,
        state: SessionMapPaneState = .ready,
        firstSeenOrder: [String]? = nil,
        updatedAt: Date? = nil,
        checkOutcome: SessionMapCheckOutcome? = nil
    ) {
        if let displayedDocument {
            focus = SessionMapInteraction.reconciledFocus(
                focus, replacing: displayedDocument, with: document)
        }
        displayedDocument = document
        if let firstSeenOrder { self.firstSeenOrder = firstSeenOrder }
        if let updatedAt { self.updatedAt = updatedAt }
        if let checkOutcome { attribution = Self.attribution(for: checkOutcome) }
        self.state = state
        if state == .ready { retainedFailureMessage = nil }
    }

    func transition(to state: SessionMapPaneState) {
        self.state = state
        if state == .ready || state == .writing { retainedFailureMessage = nil }
    }

    func retainFailure(message: String) {
        retainedFailureMessage = message
        state = .stale
    }

    func synchronizePresentation(paneWidth: CGFloat, isVisible: Bool) {
        self.paneWidth = paneWidth
        self.isVisible = isVisible
    }

    func generate(_ scope: SessionMapGenerationScope) { onGenerate(scope, false) }
    func regenerate(_ scope: SessionMapGenerationScope) { onGenerate(scope, true) }
    func caughtUp() { onCaughtUp() }
    func close() {
        isVisible = false
        onClose()
    }
    func openSettings() { onOpenSettings() }
    func perform(_ action: SessionMapAction) { onAction(action) }

    private static func attribution(for outcome: SessionMapCheckOutcome) -> String {
        switch outcome {
        case .off:
            "Generated from session. Layout checker off."
        case .skipped:
            "Generated from session. Layout unchanged, so the checker did not run."
        case .passed:
            "Generated from session. Checker passed for the rendered graph region."
        case .failed:
            "Generated from session. Checker found issues in the rendered graph region."
        case .rewrittenUnchecked:
            "Generated from session. Rewritten after checking; final revision not checked."
        case .unavailable:
            "Generated from session. Checker unavailable; final revision not checked."
        }
    }
}
