import Foundation

/// Events pushed to supervision subscribers (10x) and commands accepted back.
/// Wire format: one JSON object per line, "type" discriminates.
public enum SupervisionEvent: Equatable, Sendable {
    case sessionStarted(session: Int, harness: String)
    case sessionEnded(session: Int, harness: String)
    case windowClaimed(session: Int, harness: String, windowID: Int, app: String, title: String, bounds: String)
    case windowReleased(session: Int, windowID: Int, reason: String)
    case action(session: Int, windowID: Int, kind: String, x: Double, y: Double)
    case screenshotTaken(session: Int, windowID: Int, pngBase64: String)
    case statusChanged(session: Int, status: String)
    case stopped(reason: String)

    public func jsonLine() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    public init(jsonLine: String) throws {
        self = try JSONDecoder().decode(SupervisionEvent.self, from: Data(jsonLine.utf8))
    }
}

extension SupervisionEvent: Codable {
    private enum Kind: String, Codable {
        case sessionStarted, sessionEnded, windowClaimed, windowReleased, action, screenshotTaken, statusChanged, stopped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .sessionStarted:
            self = .sessionStarted(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness))
        case .sessionEnded:
            self = .sessionEnded(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness))
        case .windowClaimed:
            self = .windowClaimed(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness), windowID: try container.decode(Int.self, forKey: .windowID), app: try container.decode(String.self, forKey: .app), title: try container.decode(String.self, forKey: .title), bounds: try container.decode(String.self, forKey: .bounds))
        case .windowReleased:
            self = .windowReleased(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), reason: try container.decode(String.self, forKey: .reason))
        case .action:
            self = .action(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), kind: try container.decode(String.self, forKey: .kind), x: try container.decode(Double.self, forKey: .x), y: try container.decode(Double.self, forKey: .y))
        case .screenshotTaken:
            self = .screenshotTaken(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), pngBase64: try container.decode(String.self, forKey: .pngBase64))
        case .statusChanged:
            self = .statusChanged(session: try container.decode(Int.self, forKey: .session), status: try container.decode(String.self, forKey: .status))
        case .stopped:
            self = .stopped(reason: try container.decode(String.self, forKey: .reason))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStarted(let session, let harness):
            try container.encode(Kind.sessionStarted, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
        case .sessionEnded(let session, let harness):
            try container.encode(Kind.sessionEnded, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
        case .windowClaimed(let session, let harness, let windowID, let app, let title, let bounds):
            try container.encode(Kind.windowClaimed, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(app, forKey: .app)
            try container.encode(title, forKey: .title)
            try container.encode(bounds, forKey: .bounds)
        case .windowReleased(let session, let windowID, let reason):
            try container.encode(Kind.windowReleased, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(reason, forKey: .reason)
        case .action(let session, let windowID, let kind, let x, let y):
            try container.encode(Kind.action, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(kind, forKey: .kind)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case .screenshotTaken(let session, let windowID, let pngBase64):
            try container.encode(Kind.screenshotTaken, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(pngBase64, forKey: .pngBase64)
        case .statusChanged(let session, let status):
            try container.encode(Kind.statusChanged, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(status, forKey: .status)
        case .stopped(let reason):
            try container.encode(Kind.stopped, forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, session, harness, windowID, app, title, bounds, reason, kind, x, y, pngBase64, status
    }
}
