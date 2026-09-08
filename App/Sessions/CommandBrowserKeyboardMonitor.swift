import AppKit
import SwiftUI

enum CommandBrowserKeyboardEventResult: Equatable, Sendable {
    case consume
    case pass
}

enum CommandBrowserKeyboardCapturePolicy {
    nonisolated static func shouldCapture(
        _ action: ComposerCommandKeyAction,
        route: CommandBrowserRoute
    ) -> Bool {
        switch route {
        case .root:
            return true
        case .arguments:
            switch action {
            case .activate, .back:
                return true
            case .move, .cycle, .sourceIndex, .complete:
                return false
            }
        case .subcommands:
            switch action {
            case .move, .cycle, .sourceIndex, .activate, .complete, .back:
                return true
            }
        case .native:
            switch action {
            case .cycle, .sourceIndex:
                return true
            case .move, .activate, .complete, .back:
                return false
            }
        }
    }
}

enum CommandBrowserKeyboardEventRouting {
    nonisolated static func action(for event: NSEvent) -> ComposerCommandKeyAction? {
        guard event.type == .keyDown, let key = keyEquivalent(for: event) else { return nil }
        return ComposerCommandKeyRouting.route(key, modifiers: modifiers(for: event))
    }

    nonisolated static func result(
        for event: NSEvent,
        route: CommandBrowserRoute,
        handle: (ComposerCommandKeyAction) -> Bool
    ) -> CommandBrowserKeyboardEventResult {
        guard let action = action(for: event),
              CommandBrowserKeyboardCapturePolicy.shouldCapture(action, route: route),
              handle(action)
        else { return .pass }
        return .consume
    }

    private nonisolated static func modifiers(for event: NSEvent) -> EventModifiers {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    private nonisolated static func keyEquivalent(for event: NSEvent) -> KeyEquivalent? {
        switch event.keyCode {
        case 36, 76:
            return .return
        case 48:
            return .tab
        case 53:
            return .escape
        case 115:
            return .home
        case 116:
            return .pageUp
        case 119:
            return .end
        case 121:
            return .pageDown
        case 123:
            return .leftArrow
        case 125:
            return .downArrow
        case 126:
            return .upArrow
        default:
            guard let character = event.charactersIgnoringModifiers?.first else { return nil }
            return KeyEquivalent(character)
        }
    }
}

struct CommandBrowserKeyboardMonitor: NSViewRepresentable {
    let route: CommandBrowserRoute
    let onAction: @MainActor (ComposerCommandKeyAction) -> Bool

    func makeNSView(context: Context) -> CommandBrowserKeyboardMonitorView {
        CommandBrowserKeyboardMonitorView()
    }

    func updateNSView(_ view: CommandBrowserKeyboardMonitorView, context: Context) {
        view.route = route
        view.onAction = onAction
        view.startMonitoring()
    }

    static func dismantleNSView(
        _ view: CommandBrowserKeyboardMonitorView,
        coordinator: ()
    ) {
        view.stopMonitoring()
    }
}

@MainActor
final class CommandBrowserKeyboardMonitorView: NSView {
    var route: CommandBrowserRoute = .root
    var onAction: (@MainActor (ComposerCommandKeyAction) -> Bool)?

    private var keyMonitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard keyMonitor == nil, window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stopMonitoring() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        let result = CommandBrowserKeyboardEventRouting.result(
            for: event,
            route: route,
            handle: { [weak self] action in
                self?.onAction?(action) == true
            })
        return result == .consume ? nil : event
    }
}
