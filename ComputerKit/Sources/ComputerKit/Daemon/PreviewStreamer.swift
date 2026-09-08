import CoreGraphics
import Foundation

/// Pushes near-live frames of the actively controlled window to supervision
/// subscribers: immediately on each action, then on a slow heartbeat while
/// control continues. ponytail: one global active window — with N sessions the
/// last actor wins. Ceiling: N>1 sessions controlling simultaneously interleave
/// heartbeats. Upgrade path: per-session timers keyed by window.
public final class PreviewStreamer {
    private let engine: DesktopEngine
    private let interval: TimeInterval
    private let emit: (SupervisionEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var active: (session: SessionID, windowID: CGWindowID)?
    private let queue = DispatchQueue(label: "tenx-computer.preview")

    public init(engine: DesktopEngine, interval: TimeInterval = 1.0, emit: @escaping (SupervisionEvent) -> Void) {
        self.engine = engine
        self.interval = interval
        self.emit = emit
    }

    func actionOccurred(session: SessionID, windowID: CGWindowID) {
        queue.sync {
            setActiveLocked(session: session, windowID: windowID)
            emitFrameLocked()
        }
    }

    func setActive(session: SessionID?, windowID: CGWindowID?) {
        queue.sync {
            if let session, let windowID {
                setActiveLocked(session: session, windowID: windowID)
            } else {
                active = nil
                timer?.cancel()
                timer = nil
            }
        }
    }

    private func setActiveLocked(session: SessionID, windowID: CGWindowID) {
        if active?.windowID == windowID, active?.session == session, timer != nil { return }
        active = (session, windowID)
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.emitFrameLocked() }
        timer.resume()
        self.timer = timer
    }

    private func emitFrameLocked() {
        guard let active, let shot = try? engine.screenshot(windowID: active.windowID) else { return }
        emit(.screenshotTaken(session: active.session.raw, windowID: Int(active.windowID), pngBase64: shot.pngData.base64EncodedString()))
    }
}
