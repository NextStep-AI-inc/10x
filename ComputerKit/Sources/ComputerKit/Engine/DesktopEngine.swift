import CoreGraphics
import Foundation

public struct WindowInfo: Sendable, Equatable {
    public let id: CGWindowID
    public let appName: String
    public let title: String
    public let bounds: CGRect
    public let pid: pid_t
    public init(id: CGWindowID, appName: String, title: String, bounds: CGRect, pid: pid_t) {
        self.id = id
        self.appName = appName
        self.title = title
        self.bounds = bounds
        self.pid = pid
    }
}

public struct Screenshot: Sendable, Equatable {
    public let pngData: Data
    public let pixelSize: CGSize
    public let scale: Double
    public init(pngData: Data, pixelSize: CGSize, scale: Double) {
        self.pngData = pngData
        self.pixelSize = pixelSize
        self.scale = scale
    }
}

public enum MouseButton: String, Sendable, Equatable {
    case left, right
}

/// Desktop input actions. Point coordinates are window-relative, in points,
/// origin at the window's top-left. Map from PNG pixels using
/// `Screenshot.scale` and `Screenshot.pixelSize`.
public enum ComputerAction: Sendable, Equatable {
    case click(point: CGPoint, button: MouseButton)
    case doubleClick(point: CGPoint)
    case drag(from: CGPoint, to: CGPoint)
    case scroll(deltaX: Double, deltaY: Double)
    case type(String)
    case key(String) // "cmd+s", "return", "shift+tab", …
}

/// The OS-touching surface. Only MacDesktopEngine implements this for real;
/// everything else in ComputerKit is tested against fakes.
public protocol DesktopEngine {
    func preflightPermissions() -> PermissionStatus
    func listWindows() throws -> [WindowInfo]
    func screenshot(windowID: CGWindowID) throws -> Screenshot
    func launch(app: String) throws -> WindowInfo
    func act(_ action: ComputerAction, window: WindowInfo) throws
}

public struct PermissionStatus: Sendable, Equatable {
    public let screenRecording: Bool
    public let accessibility: Bool
    public var isComplete: Bool { screenRecording && accessibility }
    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }
}

public struct ComputerError: Error, Equatable, Sendable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
