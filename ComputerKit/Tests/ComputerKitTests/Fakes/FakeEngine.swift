import CoreGraphics
import Foundation
@testable import ComputerKit

final class FakeEngine: DesktopEngine {
    var windows: [WindowInfo] = []
    var screenshotPNG = Data()
    var actions: [ComputerAction] = []
    var permissionStatus = PermissionStatus(screenRecording: true, accessibility: true)
    var launchedWindow: WindowInfo?

    func preflightPermissions() -> PermissionStatus { permissionStatus }
    func listWindows() throws -> [WindowInfo] { windows }
    func screenshot(windowID: CGWindowID) throws -> Screenshot {
        Screenshot(pngData: screenshotPNG, pixelSize: CGSize(width: 100, height: 100), scale: 2)
    }
    func launch(app: String) throws -> WindowInfo {
        guard let launchedWindow else { throw ComputerError("no such app: \(app)") }
        windows.append(launchedWindow)
        return launchedWindow
    }
    func act(_ action: ComputerAction, window: WindowInfo) throws {
        actions.append(action)
    }
}
