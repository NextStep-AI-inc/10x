import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// The real engine. Every method converts failures into ComputerError so MCP
/// clients get actionable text instead of crashes.
public final class MacDesktopEngine: DesktopEngine {
    public init() {}

    public func preflightPermissions() -> PermissionStatus {
        PermissionStatus(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
    }

    public func listWindows() throws -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            throw ComputerError("window_list_unavailable")
        }
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? Int,
                  let windowID = CGWindowID(exactly: id),
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  (entry[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return WindowInfo(
                id: windowID,
                appName: entry[kCGWindowOwnerName as String] as? String ?? "?",
                title: entry[kCGWindowName as String] as? String ?? "",
                bounds: bounds,
                pid: pid_t(pid)
            )
        }
    }

    public func screenshot(windowID: CGWindowID) throws -> Screenshot {
        guard preflightPermissions().screenRecording else { throw ComputerError("permission_missing: screen_recording") }
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SyncBox<Result<Screenshot, Error>>()
        Task {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw ComputerError("window_gone: \(windowID)")
                }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let rep = NSBitmapImageRep(cgImage: image)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    throw ComputerError("screenshot_encode_failed")
                }
                resultBox.set(.success(Screenshot(
                    pngData: png,
                    pixelSize: CGSize(width: image.width, height: image.height),
                    scale: Double(image.width) / max(1, Double(window.frame.width))
                )))
            } catch let error as ComputerError {
                resultBox.set(.failure(error))
            } catch {
                resultBox.set(.failure(ComputerError("screenshot_failed: \(error.localizedDescription)")))
            }
        }
        semaphore.wait()
        guard let result = resultBox.take() else { throw ComputerError("screenshot_failed: no result") }
        return try result.get()
    }

    public func launch(app: String) throws -> WindowInfo {
        guard preflightPermissions().accessibility else { throw ComputerError("permission_missing: accessibility") }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
            ?? ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
                .lazy.map({ URL(fileURLWithPath: $0).appendingPathComponent(app + ".app") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ComputerError("app_not_found: \(app)")
        }
        let existingPIDs = Set(try listWindows().map(\.pid))
        let semaphore = DispatchSemaphore(value: 0)
        let launchedBox = SyncBox<NSRunningApplication>()
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { running, _ in
            if let running { launchedBox.set(running) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        guard let launched = launchedBox.get() else { throw ComputerError("launch_failed: \(app)") }

        // Wait for the app to present a window (up to 5s).
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let windows = try listWindows()
            if let window = windows.first(where: { $0.pid == launched.processIdentifier && !existingPIDs.contains($0.pid) })
                ?? windows.first(where: { $0.pid == launched.processIdentifier }) {
                return window
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw ComputerError("launch_no_window: \(app)")
    }

    public func act(_ action: ComputerAction, window: WindowInfo) throws {
        guard preflightPermissions().accessibility else { throw ComputerError("permission_missing: accessibility") }
        let pid = pid_t(window.pid)
        func globalPoint(_ windowRelative: CGPoint) -> CGPoint {
            CGPoint(x: window.bounds.minX + windowRelative.x, y: window.bounds.minY + windowRelative.y)
        }
        switch action {
        case .click(let point, let button):
            let location = globalPoint(point)
            let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) = button == .right
                ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
            try post(CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: location, mouseButton: cgButton), to: pid)
            try post(CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: location, mouseButton: cgButton), to: pid)
        case .doubleClick(let point):
            let location = globalPoint(point)
            for state in 1...2 {
                let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)
                let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
                down?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
                try post(down, to: pid)
                try post(up, to: pid)
            }
        case .drag(let from, let to):
            let start = globalPoint(from), end = globalPoint(to)
            try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left), to: pid)
            try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: end, mouseButton: .left), to: pid)
            try post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left), to: pid)
        case .scroll(let deltaX, let deltaY):
            try post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-deltaY), wheel2: Int32(-deltaX), wheel3: 0), to: pid)
        case .type(let text):
            for scalar in text {
                var unichar = Array(String(scalar).utf16)
                try post(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)?.applyingUnicode(&unichar), to: pid)
                try post(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)?.applyingUnicode(&unichar), to: pid)
            }
        case .key(let chord):
            let (flags, keyCode) = try KeyChord.parse(chord)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            down?.flags = flags
            up?.flags = flags
            try post(down, to: pid)
            try post(up, to: pid)
        }
    }

    private func post(_ event: CGEvent?, to pid: pid_t) throws {
        guard let event else { throw ComputerError("event_create_failed") }
        // ponytail: background delivery only, by design — the agent never steals
        // focus. Ceiling: some apps ignore posted-to-pid events. Upgrade path:
        // CGEventPostToPSN / Skylight private APIs (see pi-natives skylight.rs).
        event.postToPid(pid)
    }
}

private extension CGEvent {
    func applyingUnicode(_ chars: inout [UniChar]) -> CGEvent {
        keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        return self
    }
}

/// Thread-safe box for bridging async callbacks to synchronous engine methods.
private final class SyncBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?

    func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func take() -> T? {
        lock.lock()
        defer { lock.unlock() }
        let current = value
        value = nil
        return current
    }

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
