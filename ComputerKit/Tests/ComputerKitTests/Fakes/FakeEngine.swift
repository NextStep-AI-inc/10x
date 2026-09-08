import CoreGraphics
import Foundation
import ComputerKit

final class FakeEngine: DesktopEngine {
    var windows: [WindowInfo] = []
    var offScreenWindowIDs: Set<CGWindowID> = []
    var screenshotPNG = Data()
    var actions: [ComputerAction] = []
    var permissionStatus = PermissionStatus(screenRecording: true, accessibility: true)
    var launchedWindow: WindowInfo?
    var screenshotShouldFail = false
    var screenshotError: ComputerError?
    var isCancelled: @Sendable () -> Bool = { false }

    /// When set, `act` blocks until `releaseActBlock()` is called (for stop_all concurrency tests).
    var actBlock: DispatchSemaphore?

    func preflightPermissions() -> PermissionStatus { permissionStatus }

    func listWindows(onScreenOnly: Bool = true) throws -> [WindowInfo] {
        if onScreenOnly {
            return windows.filter { !offScreenWindowIDs.contains($0.id) }
        }
        return windows
    }

    func screenshot(windowID: CGWindowID) throws -> Screenshot {
        if let screenshotError { throw screenshotError }
        if screenshotShouldFail { throw ComputerError("screenshot_failed") }
        if !windows.contains(where: { $0.id == windowID }) {
            throw ComputerError("window_gone: \(windowID)")
        }
        return Screenshot(pngData: screenshotPNG, pixelSize: CGSize(width: 100, height: 100), scale: 2)
    }

    func launch(app: String) throws -> WindowInfo {
        if isCancelled() { throw ComputerError("aborted: shut-off") }
        guard let launchedWindow else { throw ComputerError("no such app: \(app)") }
        windows.append(launchedWindow)
        return launchedWindow
    }

    func act(_ action: ComputerAction, window: WindowInfo) throws {
        actBlock?.wait()
        if isCancelled() { throw ComputerError("aborted: shut-off") }
        if case .type(let text) = action {
            for scalar in text {
                if isCancelled() { throw ComputerError("aborted: shut-off") }
                _ = scalar
            }
        }
        actions.append(action)
    }

    func releaseActBlock() {
        actBlock?.signal()
    }
}
