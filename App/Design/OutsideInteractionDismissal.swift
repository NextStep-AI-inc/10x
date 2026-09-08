import AppKit
import SwiftUI

/// Closes a composer shelf on the first mouse-down that lands outside its
/// silhouette, and whenever the window stops being key.
///
/// A SwiftUI scrim cannot do this job here: the rail and the usage dock draw
/// above the route canvas, so no view inside the composer can cover them. A
/// window-level event monitor sees every click whatever the z-order, and
/// hit-testing the shelf's own shape keeps its stepped cut-out from counting as
/// inside the panel.
struct OutsideInteractionDismissal<Silhouette: Shape>: ViewModifier {
    let silhouette: Silhouette
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.background {
            OutsideInteractionMonitor(
                contains: { bounds, point in
                    silhouette.path(in: bounds).contains(point)
                },
                onDismiss: onDismiss)
        }
    }
}

extension View {
    /// Dismisses this shelf when the pointer acts anywhere outside `silhouette`.
    func dismissesOnOutsideInteraction<Silhouette: Shape>(
        silhouette: Silhouette,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(OutsideInteractionDismissal(silhouette: silhouette, onDismiss: onDismiss))
    }
}

private struct OutsideInteractionMonitor: NSViewRepresentable {
    let contains: (CGRect, CGPoint) -> Bool
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> OutsideInteractionMonitorView {
        OutsideInteractionMonitorView()
    }

    func updateNSView(_ view: OutsideInteractionMonitorView, context: Context) {
        view.contains = contains
        view.onDismiss = onDismiss
    }

    static func dismantleNSView(
        _ view: OutsideInteractionMonitorView,
        coordinator: ()
    ) {
        view.stopMonitoring()
    }
}

/// Flipped so AppKit hands back top-left coordinates, which is the space
/// `Shape.path(in:)` draws in.
private final class OutsideInteractionMonitorView: NSView {
    var contains: ((CGRect, CGPoint) -> Bool)?
    var onDismiss: (() -> Void)?

    private var mouseMonitor: Any?
    private var resignKeyTask: Task<Void, Never>?

    override var isFlipped: Bool { true }

    /// Never intercepts a click. The shelf paints its own fill, and the region
    /// between the silhouette and this view's bounding box belongs to whatever
    /// sits underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    /// Teardown is driven by the view's window lifecycle and by
    /// `dismantleNSView`, never by `deinit`: a nonisolated `deinit` cannot touch
    /// either token under strict concurrency.
    func stopMonitoring() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        resignKeyTask?.cancel()
        resignKeyTask = nil
    }

    private func startMonitoring() {
        guard mouseMonitor == nil else { return }
        // The event is returned unchanged: one click both dismisses the shelf
        // and reaches what it landed on, which is what every other control in
        // the app does.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.dismissIfOutside(event)
            return event
        }
        let notifications = NotificationCenter.default.notifications(
            named: NSWindow.didResignKeyNotification,
            object: window)
        resignKeyTask = Task { @MainActor [weak self] in
            for await _ in notifications {
                guard let self else { return }
                onDismiss?()
            }
        }
    }

    private func dismissIfOutside(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard contains?(bounds, point) != true else { return }
        onDismiss?()
    }
}
