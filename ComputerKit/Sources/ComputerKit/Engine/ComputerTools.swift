import CoreGraphics
import Foundation

/// Implements the seven-tool MCP surface for one harness session.
public final class ComputerTools: MCPToolProviding {
    private let engine: DesktopEngine
    private let registry: SessionRegistry
    private let session: SessionID

    public init(engine: DesktopEngine, registry: SessionRegistry, session: SessionID) {
        self.engine = engine
        self.registry = registry
        self.session = session
    }

    public var tools: [MCPTool] {
        let windowIDProperty: JSONValue = .object(["type": .string("number"), "description": .string("Window id from computer_windows")])
        let windowID: [String: JSONValue] = ["window_id": windowIDProperty]
        func schema(_ properties: [String: JSONValue], _ required: [String]) -> JSONValue {
            .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
            ])
        }
        return [
            MCPTool(name: "computer_windows", description: "List visible windows: id, app, title, bounds, claimed-by.", inputSchema: schema([:], [])),
            MCPTool(name: "computer_screenshot", description: "Capture a claimed window. Returns an image plus size/scale for coordinate mapping.", inputSchema: schema(windowID, ["window_id"])),
            MCPTool(name: "computer_status", description: "Set the status text shown on your window tag (e.g. \"Running tests…\").", inputSchema: schema(["status": .object(["type": .string("string")])], ["status"])),
            MCPTool(name: "computer_launch", description: "Launch an application by name; its new window is claimed for you.", inputSchema: schema(["app": .object(["type": .string("string")])], ["app"])),
            MCPTool(name: "computer_claim", description: "Claim an existing window by id. Only one session may own a window.", inputSchema: schema(windowID, ["window_id"])),
            MCPTool(name: "computer_release", description: "Release a window you claimed.", inputSchema: schema(windowID, ["window_id"])),
            MCPTool(name: "computer_act", description: "Act on a claimed window at window-relative coordinates. action: click|double_click|right_click|drag|scroll|type|key.", inputSchema: schema([
                "window_id": windowIDProperty,
                "action": .object(["type": .string("string")]),
                "x": .object(["type": .string("number")]),
                "y": .object(["type": .string("number")]),
                "to_x": .object(["type": .string("number")]),
                "to_y": .object(["type": .string("number")]),
                "delta_x": .object(["type": .string("number")]),
                "delta_y": .object(["type": .string("number")]),
                "text": .object(["type": .string("string")]),
                "keys": .object(["type": .string("string"), "description": .string("e.g. \"cmd+s\", \"return\"")]),
                "button": .object(["type": .string("string"), "description": .string("left|right")]),
            ], ["window_id", "action"])),
        ]
    }

    public func callTool(name: String, arguments: JSONValue) throws -> MCPResult {
        guard registry.isActive(session) else { throw ComputerError("session_stopped") }
        switch name {
        case "computer_windows":
            let items = try engine.listWindows(onScreenOnly: true).map { window -> JSONValue in
                var object: [String: JSONValue] = [
                    "id": .number(Double(window.id)),
                    "app": .string(window.appName),
                    "title": .string(window.title),
                    "bounds": .string("\(Int(window.bounds.minX)),\(Int(window.bounds.minY)) \(Int(window.bounds.width))x\(Int(window.bounds.height))"),
                ]
                if let owner = registry.owner(of: window.id), let info = registry.session(owner) {
                    object["claimed_by"] = .string("session \(owner) (\(info.harness))")
                }
                return .object(object)
            }
            let data = try JSONEncoder().encode(JSONValue.array(items))
            return .text(String(decoding: data, as: UTF8.self))

        case "computer_claim":
            let window = try windowArgument(arguments, mustBeClaimed: false)
            try registry.claim(window, for: session)
            return .text("claimed window \(window.id) (\(window.appName))")

        case "computer_release":
            let windowID = try windowIDArgument(arguments)
            guard registry.owner(of: windowID) == session else { throw ComputerError("window_not_claimed: \(windowID)") }
            registry.release(windowID)
            return .text("released window \(windowID)")

        case "computer_screenshot":
            let window = try claimedWindow(arguments)
            let shot = try engine.screenshot(windowID: window.id)
            return .image(
                pngBase64: shot.pngData.base64EncodedString(),
                text: "\(window.appName) window \(window.id) — \(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))px @\(shot.scale)x; window size \(Int(window.bounds.width))x\(Int(window.bounds.height))pt; coordinates for computer_act are window-relative points"
            )

        case "computer_status":
            guard let status = arguments["status"]?.stringValue else { throw MCPError.invalidParams("computer_status requires status") }
            registry.setStatus(String(status.prefix(80)), for: session)
            return .text("status set")

        case "computer_launch":
            guard let app = arguments["app"]?.stringValue else { throw MCPError.invalidParams("computer_launch requires app") }
            let window = try engine.launch(app: app)
            try registry.claim(window, for: session)
            return .text("launched \(app); claimed window \(window.id) (\(Int(window.bounds.width))x\(Int(window.bounds.height))pt)")

        case "computer_act":
            let window = try claimedWindow(arguments)
            let action = try parseAction(arguments, window: window)
            try engine.act(action, window: window)
            return .text("done")

        default:
            throw MCPError.methodNotFound(name)
        }
    }

    private func windowIDArgument(_ arguments: JSONValue) throws -> CGWindowID {
        guard let id = arguments["window_id"]?.intValue,
              let windowID = CGWindowID(exactly: id) else {
            throw MCPError.invalidParams("requires window_id")
        }
        return windowID
    }

    private func windowArgument(_ arguments: JSONValue, mustBeClaimed: Bool) throws -> WindowInfo {
        let windowID = try windowIDArgument(arguments)
        guard let window = try engine.listWindows(onScreenOnly: false).first(where: { $0.id == windowID }) ?? registry.window(windowID) else {
            throw ComputerError("window_gone: \(windowID)")
        }
        if mustBeClaimed, registry.owner(of: windowID) != session {
            throw ComputerError("window_not_claimed: \(windowID)")
        }
        return window
    }

    private func claimedWindow(_ arguments: JSONValue) throws -> WindowInfo {
        try windowArgument(arguments, mustBeClaimed: true)
    }

    private func clampX(_ x: Double, width: CGFloat) -> Double {
        Double(min(max(x, 0), Double(width) - 1))
    }

    private func clampY(_ y: Double, height: CGFloat) -> Double {
        Double(min(max(y, 0), Double(height) - 1))
    }

    private func parseAction(_ arguments: JSONValue, window: WindowInfo) throws -> ComputerAction {
        guard let action = arguments["action"]?.stringValue else { throw MCPError.invalidParams("computer_act requires action") }
        let w = window.bounds.width
        let h = window.bounds.height
        func point(_ x: String, _ y: String) throws -> CGPoint {
            guard let xValue = arguments[x]?.doubleValue, let yValue = arguments[y]?.doubleValue else {
                throw MCPError.invalidParams("\(action) requires \(x)/\(y)")
            }
            return CGPoint(x: clampX(xValue, width: w), y: clampY(yValue, height: h))
        }
        switch action {
        case "click":
            let button: MouseButton
            if let buttonArg = arguments["button"]?.stringValue {
                switch buttonArg {
                case "left": button = .left
                case "right": button = .right
                default: throw MCPError.invalidParams("button must be left or right")
                }
            } else {
                button = .left
            }
            return .click(point: try point("x", "y"), button: button)
        case "double_click": return .doubleClick(point: try point("x", "y"))
        case "right_click": return .click(point: try point("x", "y"), button: .right)
        case "drag": return .drag(from: try point("x", "y"), to: try point("to_x", "to_y"))
        case "scroll":
            func scrollDelta(_ key: String) throws -> Double? {
                guard let value = arguments[key] else { return nil }
                guard let delta = value.doubleValue else {
                    throw MCPError.invalidParams("scroll requires numeric \(key)")
                }
                return delta
            }
            let deltaX = try scrollDelta("delta_x")
            let deltaY = try scrollDelta("delta_y")
            guard deltaX != nil || deltaY != nil else {
                throw MCPError.invalidParams("scroll requires delta_x and/or delta_y")
            }
            return .scroll(deltaX: deltaX ?? 0, deltaY: deltaY ?? 0)
        case "type":
            guard let text = arguments["text"]?.stringValue else { throw MCPError.invalidParams("type requires text") }
            return .type(text)
        case "key":
            guard let keys = arguments["keys"]?.stringValue else { throw MCPError.invalidParams("key requires keys") }
            return .key(keys)
        default:
            throw ComputerError("invalid_action: \(action)")
        }
    }
}

/// Supervision action-event coordinates derived from tool args and window bounds.
enum ActionEventPoints {
    static func from(arguments: JSONValue?, window: WindowInfo?) -> (x: Double?, y: Double?) {
        guard let action = arguments?["action"]?.stringValue else { return (nil, nil) }
        let w = window?.bounds.width ?? 0
        let h = window?.bounds.height ?? 0
        func clampX(_ x: Double) -> Double { min(max(x, 0), Double(w) - 1) }
        func clampY(_ y: Double) -> Double { min(max(y, 0), Double(h) - 1) }
        switch action {
        case "click", "double_click", "right_click":
            guard let x = arguments?["x"]?.doubleValue, let y = arguments?["y"]?.doubleValue else { return (nil, nil) }
            return (clampX(x), clampY(y))
        case "drag":
            guard let x = arguments?["to_x"]?.doubleValue, let y = arguments?["to_y"]?.doubleValue else { return (nil, nil) }
            return (clampX(x), clampY(y))
        case "scroll":
            guard w > 0, h > 0 else { return (nil, nil) }
            return (Double(w / 2), Double(h / 2))
        case "type", "key":
            return (nil, nil)
        default:
            return (nil, nil)
        }
    }
}
