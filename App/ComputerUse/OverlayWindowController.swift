import AppKit
import ComputerKit
import SwiftUI

/// Owns one click-through NSPanel per claimed window, driven by OverlayModel.
/// ponytail: panels reposition on a 0.5s CGWindowList poll. Ceiling: overlays
/// lag fast window drags. Upgrade path: CGS window-move notifications.
@MainActor
final class OverlayWindowController {
    private let model = OverlayModel()
    private var panels: [Int: NSPanel] = [:]
    private var pollTimer: Timer?

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }

    func apply(_ event: SupervisionEvent) {
        model.apply(event)
        syncPanels()
    }

    private func poll() {
        model.pollBounds { windowID in
            guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowID)) as? [[String: Any]],
                  let entry = list.first,
                  let dict = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return rect
        }
        syncPanels()
    }

    private func syncPanels() {
        for (windowID, state) in model.overlays {
            let panel = panels[windowID] ?? makePanel(windowID: windowID)
            // macOS window coords are bottom-left origin; panels use the same.
            panel.setFrame(state.frame.insetBy(dx: -6, dy: -6), display: true)
            (panel.contentView as? NSHostingView<ComputerUseOverlayView>)?.rootView = ComputerUseOverlayView(state: state)
            panel.orderFrontRegardless()
        }
        let gone = panels.keys.filter { model.overlays[$0] == nil }
        for windowID in gone {
            panels[windowID]?.close()
            panels.removeValue(forKey: windowID)
        }
    }

    private func makePanel(windowID: Int) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ComputerUseOverlayView(state: model.overlays[windowID]!))
        panels[windowID] = panel
        return panel
    }
}
