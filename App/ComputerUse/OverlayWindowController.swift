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
    private var isStopped = false

    func start() {
        guard pollTimer == nil else { return }
        isStopped = false
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        isStopped = true
        pollTimer?.invalidate()
        pollTimer = nil
        model.removeAll()
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }

    func apply(_ event: SupervisionEvent) {
        guard !isStopped else { return }
        model.apply(event)
        syncPanels()
    }

    private func poll() {
        model.pollBounds { windowID in
            guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowID)) as? [[String: Any]],
                  let entry = list.first,
                  let dict = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            let isOnscreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            return (rect, isOnscreen)
        }
        syncPanels()
    }

    private func syncPanels() {
        for (windowID, state) in model.overlays {
            let panel = panels[windowID] ?? makePanel(windowID: windowID)
            guard state.isOnscreen else {
                panel.orderOut(nil)
                continue
            }
            panel.setFrame(panelFrame(for: state.frame), display: true)
            if let hosting = panel.contentView as? NSHostingView<ComputerUseOverlayView>,
               hosting.rootView.state != state {
                hosting.rootView = ComputerUseOverlayView(state: state)
            }
            panel.orderFrontRegardless()
        }
        let gone = panels.keys.filter { model.overlays[$0] == nil }
        for windowID in gone {
            panels[windowID]?.close()
            panels.removeValue(forKey: windowID)
        }
    }

    /// CGWindowList reports Quartz screen coords (top-left origin, Y down);
    /// NSPanel.setFrame expects Cocoa (bottom-left origin, Y up). Convert once,
    /// here. The cursor stays window-relative inside the panel — never flipped.
    private func panelFrame(for quartz: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var frame = CGRect(
            x: quartz.minX,
            y: primaryHeight - quartz.minY - quartz.height,
            width: quartz.width,
            height: quartz.height
        ).insetBy(dx: -ComputerUseOverlayView.sideInset, dy: -ComputerUseOverlayView.sideInset)
        // Headroom above the window for the session tag (Cocoa: grow toward maxY).
        frame.size.height += ComputerUseOverlayView.tagHeadroom - ComputerUseOverlayView.sideInset
        return frame
    }

    private func makePanel(windowID: Int) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false // the point is watching OTHER apps' windows
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ComputerUseOverlayView(state: model.overlays[windowID]!))
        panels[windowID] = panel
        return panel
    }
}
