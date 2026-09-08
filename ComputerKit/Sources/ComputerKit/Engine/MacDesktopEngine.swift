import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// The real engine. Every method converts failures into ComputerError so MCP
/// clients get actionable text instead of crashes.
public final class MacDesktopEngine: DesktopEngine {
    private static let localEventFilter: UInt32 = 0x01 | 0x02 | 0x04

    public var isCancelled: @Sendable () -> Bool = { false }

    private let eventSource: CGEventSource = {
        let source = CGEventSource(stateID: .hidSystemState)!
        CGEventSourceSetLocalEventsSuppressionInterval(source, 0)
        CGEventSourceSetLocalEventsFilterDuringSuppressionState(source, localEventFilter, 0)
        CGEventSourceSetLocalEventsFilterDuringSuppressionState(source, localEventFilter, 1)
        return source
    }()

    public init() {}

    public func preflightPermissions() -> PermissionStatus {
        PermissionStatus(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
    }

    public func listWindows(onScreenOnly: Bool = true) throws -> [WindowInfo] {
        var options: CGWindowListOption = [.excludeDesktopElements]
        if onScreenOnly { options.insert(.optionOnScreenOnly) }
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
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
        if Thread.isMainThread {
            return try DispatchQueue.global(qos: .userInitiated).sync {
                try captureScreenshot(windowID: windowID)
            }
        }
        return try captureScreenshot(windowID: windowID)
    }

    private func captureScreenshot(windowID: CGWindowID) throws -> Screenshot {
        guard preflightPermissions().screenRecording else { throw ComputerError("permission_missing: screen_recording") }
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SyncBox<Result<Screenshot, Error>>()
        Task {
            defer { semaphore.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw ComputerError("window_gone: \(windowID)")
                }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                configuration.showsCursor = false
                configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
                configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let png = try encodePNG(from: image)
                resultBox.set(.success(Screenshot(
                    pngData: png,
                    pixelSize: CGSize(width: image.width, height: image.height),
                    scale: Double(filter.pointPixelScale)
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
            ?? ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
                .lazy.map({ URL(fileURLWithPath: $0).appendingPathComponent(app + ".app") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ComputerError("app_not_found: \(app)")
        }
        let bundleID = Bundle(url: appURL)?.bundleIdentifier
        let preLaunchWindowIDs: Set<CGWindowID>
        if let bundleID,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            preLaunchWindowIDs = Set(try listWindows(onScreenOnly: true).filter { $0.pid == running.processIdentifier }.map(\.id))
        } else {
            preLaunchWindowIDs = []
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SyncBox<Result<NSRunningApplication, Error>>()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { running, error in
            if let error {
                resultBox.set(.failure(ComputerError("launch_failed: \(error.localizedDescription)")))
            } else if let running {
                resultBox.set(.success(running))
            } else {
                resultBox.set(.failure(ComputerError("launch_failed: \(app)")))
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        guard let launched = try resultBox.take()?.get() else {
            throw ComputerError("launch_failed: \(app)")
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if isCancelled() { throw ComputerError("aborted: shut-off") }
            let windows = try listWindows(onScreenOnly: true)
            if let window = windows.first(where: { $0.pid == launched.processIdentifier && !preLaunchWindowIDs.contains($0.id) }) {
                return window
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw ComputerError("launch_no_new_window: \(app)")
    }

    public func act(_ action: ComputerAction, window: WindowInfo) throws {
        guard preflightPermissions().accessibility else { throw ComputerError("permission_missing: accessibility") }
        let pid = window.pid
        let wid = window.id
        switch action {
        case .type, .key:
            let siblings = try listWindows(onScreenOnly: true).filter { $0.pid == pid }.count
            if siblings > 1 {
                throw ComputerError(
                    "background_unavailable: window \(wid) is one of \(siblings) windows in its application; background keystrokes go to whichever window is key"
                )
            }
        default:
            break
        }
        // Hold synthetic keyboard focus only for the duration of this action —
        // keeping it would misroute the user's real keystrokes (observed live).
        let focusToken = try SkyLight.acquireBackgroundFocus(pid: pid, wid: wid)
        defer { SkyLight.releaseBackgroundFocus(focusToken) }
        switch action {
        case .click(let point, let button):
            let group = clickGroupID()
            let (downType, upType, cgButton, buttonNumber) = buttonTypes(button)
            try postMouse(
                pid: pid, wid: wid, window: window, type: downType, button: cgButton,
                x: point.x, y: point.y, phase: 3, clickState: 1, buttonNumber: buttonNumber, group: group
            )
            Thread.sleep(forTimeInterval: 0.001)
            try postMouse(
                pid: pid, wid: wid, window: window, type: upType, button: cgButton,
                x: point.x, y: point.y, phase: 3, clickState: 1, buttonNumber: buttonNumber, group: group
            )
        case .doubleClick(let point):
            let group = clickGroupID()
            for clickState in 1...2 {
                try postMouse(
                    pid: pid, wid: wid, window: window, type: .leftMouseDown, button: .left,
                    x: point.x, y: point.y, phase: 3, clickState: Int64(clickState), buttonNumber: 0, group: group
                )
                Thread.sleep(forTimeInterval: 0.001)
                try postMouse(
                    pid: pid, wid: wid, window: window, type: .leftMouseUp, button: .left,
                    x: point.x, y: point.y, phase: 3, clickState: Int64(clickState), buttonNumber: 0, group: group
                )
                if clickState < 2 { Thread.sleep(forTimeInterval: 0.08) }
            }
        case .drag(let from, let to):
            let group = clickGroupID()
            try postMouse(
                pid: pid, wid: wid, window: window, type: .leftMouseDown, button: .left,
                x: from.x, y: from.y, phase: 3, clickState: 1, buttonNumber: 0, group: group
            )
            let steps = 6
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                Thread.sleep(forTimeInterval: 0.016)
                try postMouse(
                    pid: pid, wid: wid, window: window, type: .leftMouseDragged, button: .left,
                    x: point.x, y: point.y, phase: 3, clickState: 1, buttonNumber: 0, group: group
                )
            }
            Thread.sleep(forTimeInterval: 0.05)
            try postMouse(
                pid: pid, wid: wid, window: window, type: .leftMouseUp, button: .left,
                x: to.x, y: to.y, phase: 3, clickState: 1, buttonNumber: 0, group: group
            )
        case .scroll(let deltaX, let deltaY):
            let group = clickGroupID()
            let center = CGPoint(x: window.bounds.width / 2, y: window.bounds.height / 2)
            try postMouse(
                pid: pid, wid: wid, window: window, type: .mouseMoved, button: .left,
                x: center.x, y: center.y, phase: 2, clickState: 0, buttonNumber: 0, group: group
            )
            Thread.sleep(forTimeInterval: 0.015)
            guard let event = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: clampScrollWheel(-deltaY),
                wheel2: clampScrollWheel(-deltaX),
                wheel3: 0
            ) else {
                throw ComputerError("event_create_failed")
            }
            event.location = globalPoint(center, in: window)
            try SkyLight.stamp(
                event: event, pid: pid, wid: wid,
                windowLocal: center,
                phase: 3, clickState: 0, button: 0, clickGroup: group
            )
            try postStamped(event, pid: pid, windowID: wid, keyboard: false)
        case .type(let text):
            for scalar in text {
                if isCancelled() { throw ComputerError("aborted: shut-off") }
                var unichar = Array(String(scalar).utf16)
                try postKeyboard(CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)?.applyingUnicode(&unichar), pid: pid, windowID: wid)
                Thread.sleep(forTimeInterval: 0.008)
                try postKeyboard(CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false)?.applyingUnicode(&unichar), pid: pid, windowID: wid)
                Thread.sleep(forTimeInterval: 0.008)
            }
        case .key(let chord):
            let (modifiers, keyCode) = try KeyChord.parse(chord)
            for modifier in modifiers {
                try postKeyboard(CGEvent(keyboardEventSource: eventSource, virtualKey: modifier, keyDown: true), pid: pid, windowID: wid)
                Thread.sleep(forTimeInterval: 0.008)
            }
            try postKeyboard(CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true), pid: pid, windowID: wid)
            Thread.sleep(forTimeInterval: 0.008)
            try postKeyboard(CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false), pid: pid, windowID: wid)
            Thread.sleep(forTimeInterval: 0.008)
            for modifier in modifiers.reversed() {
                try postKeyboard(CGEvent(keyboardEventSource: eventSource, virtualKey: modifier, keyDown: false), pid: pid, windowID: wid)
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
    }

    private func postMouse(
        pid: pid_t,
        wid: CGWindowID,
        window: WindowInfo,
        type: CGEventType,
        button: CGMouseButton,
        x: CGFloat,
        y: CGFloat,
        phase: Int64,
        clickState: Int64,
        buttonNumber: Int64,
        group: Int64
    ) throws {
        let screenPoint = globalPoint(CGPoint(x: x, y: y), in: window)
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: screenPoint,
            mouseButton: button
        ) else {
            throw ComputerError("event_create_failed")
        }
        try SkyLight.stamp(
            event: event, pid: pid, wid: wid, windowLocal: CGPoint(x: x, y: y),
            phase: phase, clickState: clickState, button: buttonNumber, clickGroup: group
        )
        try postStamped(event, pid: pid, windowID: wid, keyboard: false)
    }

    private func postKeyboard(_ event: CGEvent?, pid: pid_t, windowID: CGWindowID) throws {
        guard let event else { throw ComputerError("event_create_failed") }
        try postStamped(event, pid: pid, windowID: windowID, keyboard: true)
    }

    private func postStamped(_ event: CGEvent, pid: pid_t, windowID: CGWindowID, keyboard: Bool) throws {
        if kill(pid, 0) == -1, errno == ESRCH {
            throw ComputerError("window_gone: \(windowID)")
        }
        // ponytail: background delivery only, by design — the agent never steals
        // focus. Ceiling: SkyLight private SPI; multi-window processes reject
        // background keyboard; symbols probed at runtime.
        if keyboard {
            try SkyLight.postKeyboard(pid: pid, event: event)
        } else {
            try SkyLight.postDual(pid: pid, event: event)
        }
    }

    private func globalPoint(_ windowRelative: CGPoint, in window: WindowInfo) -> CGPoint {
        CGPoint(x: window.bounds.minX + windowRelative.x, y: window.bounds.minY + windowRelative.y)
    }

    private func buttonTypes(_ button: MouseButton) -> (CGEventType, CGEventType, CGMouseButton, Int64) {
        switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left, 0)
        case .right: (.rightMouseDown, .rightMouseUp, .right, 1)
        }
    }

    private func clickGroupID() -> Int64 {
        var timespec = timespec()
        clock_gettime(CLOCK_REALTIME, &timespec)
        return Int64(timespec.tv_nsec)
    }

    private func clampScrollWheel(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(min(Double(Int32.max), max(Double(Int32.min), value)))
    }
}

@_silgen_name("CGEventSourceSetLocalEventsSuppressionInterval")
private func CGEventSourceSetLocalEventsSuppressionInterval(_ source: CGEventSource, _ seconds: CFTimeInterval)

@_silgen_name("CGEventSourceSetLocalEventsFilterDuringSuppressionState")
private func CGEventSourceSetLocalEventsFilterDuringSuppressionState(_ source: CGEventSource, _ filter: UInt32, _ state: UInt32)

private func encodePNG(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw ComputerError("screenshot_encode_failed")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ComputerError("screenshot_encode_failed")
    }
    return data as Data
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
}
