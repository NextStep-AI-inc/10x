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
    var onWindowGone: ((SessionID, CGWindowID) -> Void)?
    private var timer: DispatchSourceTimer?
    private var active: (session: SessionID, windowID: CGWindowID)?
    private let queue = DispatchQueue(label: "tenx-computer.preview")

    public init(engine: DesktopEngine, interval: TimeInterval = 1.0, emit: @escaping (SupervisionEvent) -> Void) {
        self.engine = engine
        self.interval = interval
        self.emit = emit
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }

    func actionOccurred(session: SessionID, windowID: CGWindowID) {
        let outcome = queue.sync {
            setActiveLocked(session: session, windowID: windowID)
            return captureOutcomeLocked()
        }
        guard let outcome else { return }
        if let gone = outcome.gone { onWindowGone?(gone.0, gone.1) }
        if let event = outcome.event { emit(event) }
    }

    func setActive(session: SessionID?, windowID: CGWindowID?) {
        queue.sync {
            if let session, let windowID {
                setActiveLocked(session: session, windowID: windowID)
            } else {
                clearActiveLocked()
            }
        }
    }

    func stopPreview(for session: SessionID) {
        queue.sync {
            guard active?.session == session else { return }
            clearActiveLocked()
        }
    }

    func stopPreview(for session: SessionID, windowID: CGWindowID) {
        queue.sync {
            guard active?.session == session, active?.windowID == windowID else { return }
            clearActiveLocked()
        }
    }

    private func setActiveLocked(session: SessionID, windowID: CGWindowID) {
        if active?.windowID == windowID, active?.session == session, timer != nil { return }
        active = (session, windowID)
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.heartbeatLocked() }
        timer.resume()
        self.timer = timer
    }

    private func clearActiveLocked() {
        active = nil
        timer?.cancel()
        timer = nil
    }

    private func heartbeatLocked() {
        guard let outcome = captureOutcomeLocked() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if let gone = outcome.gone { self?.onWindowGone?(gone.0, gone.1) }
            if let event = outcome.event { self?.emit(event) }
        }
    }

    private struct CaptureOutcome {
        var event: SupervisionEvent?
        var gone: (SessionID, CGWindowID)?
    }

    private func captureOutcomeLocked() -> CaptureOutcome? {
        guard let active else { return nil }
        do {
            let shot = try engine.screenshot(windowID: active.windowID)
            return CaptureOutcome(
                event: .screenshotTaken(
                    session: active.session.raw, windowID: Int(active.windowID),
                    pngBase64: shot.pngData.base64EncodedString(),
                    width: Int(shot.pixelSize.width),
                    height: Int(shot.pixelSize.height),
                    scale: shot.scale
                ),
                gone: nil
            )
        } catch let error as ComputerError where error.message.hasPrefix("window_gone") {
            let session = active.session
            let windowID = active.windowID
            clearActiveLocked()
            return CaptureOutcome(event: nil, gone: (session, windowID))
        } catch {
            return CaptureOutcome(event: nil, gone: nil)
        }
    }
}
