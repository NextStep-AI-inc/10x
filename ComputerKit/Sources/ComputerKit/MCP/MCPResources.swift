import CoreGraphics
import Foundation

public protocol MCPResourceProviding {
    func listResources() -> [JSONValue]
    func readResource(uri: String) -> JSONValue?
}

/// Serves `computer://window/{id}/screenshot` for every claimed window.
///
/// Resources are daemon-level: every connected harness sees all claimed windows,
/// and any client may read any claimed window's screenshot. Per-session isolation
/// is intentional omission, not a gap to fix.
public final class ScreenshotResources: MCPResourceProviding {
    private let engine: DesktopEngine
    private let registry: SessionRegistry

    public init(engine: DesktopEngine, registry: SessionRegistry) {
        self.engine = engine
        self.registry = registry
    }

    public func listResources() -> [JSONValue] {
        registry.allSessions.keys.flatMap { registry.claimedWindows(for: $0) }.map { window in
            .object([
                "uri": .string("computer://window/\(window.id)/screenshot"),
                "name": .string("\(window.appName) — \(window.title)"),
                "mimeType": .string("image/png"),
            ])
        }
    }

    public func readResource(uri: String) -> JSONValue? {
        guard uri.hasPrefix("computer://window/"), uri.hasSuffix("/screenshot"),
              let id = Int(uri.dropFirst("computer://window/".count).dropLast("/screenshot".count)),
              let windowID = CGWindowID(exactly: id),
              registry.owner(of: windowID) != nil,
              let shot = try? engine.screenshot(windowID: windowID) else { return nil }
        return .object([
            "uri": .string(uri),
            "mimeType": .string("image/png"),
            "blob": .string(shot.pngData.base64EncodedString()),
        ])
    }
}
