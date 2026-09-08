import Foundation

/// Events pushed to supervision subscribers (10x).
/// Wire format: one JSON object per line, "type" discriminates.
/// `screenshotTaken` lines can be megabytes (full window PNG, base64).
/// `jsonLine()` returns the JSON object only — the broadcaster must append `0x0A` (newline).
public enum SupervisionEvent: Equatable, Sendable {
    case sessionStarted(session: Int, harness: String, label: String?, pid: Int32?)
    case sessionEnded(session: Int, harness: String)
    case windowClaimed(session: Int, harness: String, windowID: Int, app: String, title: String, bounds: String)
    case windowReleased(session: Int, windowID: Int, reason: String)
    case action(session: Int, windowID: Int, kind: String, x: Double?, y: Double?)
    case screenshotTaken(session: Int, windowID: Int, pngBase64: String, width: Int, height: Int, scale: Double)
    case statusChanged(session: Int, status: String)
    case permissions(screenRecording: Bool, accessibility: Bool)
    case stopped(reason: String, session: Int?)

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
        case sessionStarted, sessionEnded, windowClaimed, windowReleased, action, screenshotTaken, statusChanged, permissions, stopped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .sessionStarted:
            self = .sessionStarted(
                session: try container.decode(Int.self, forKey: .session),
                harness: try container.decode(String.self, forKey: .harness),
                label: try container.decodeIfPresent(String.self, forKey: .label),
                pid: try container.decodeIfPresent(Int32.self, forKey: .pid)
            )
        case .sessionEnded:
            self = .sessionEnded(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness))
        case .windowClaimed:
            self = .windowClaimed(session: try container.decode(Int.self, forKey: .session), harness: try container.decode(String.self, forKey: .harness), windowID: try container.decode(Int.self, forKey: .windowID), app: try container.decode(String.self, forKey: .app), title: try container.decode(String.self, forKey: .title), bounds: try container.decode(String.self, forKey: .bounds))
        case .windowReleased:
            self = .windowReleased(session: try container.decode(Int.self, forKey: .session), windowID: try container.decode(Int.self, forKey: .windowID), reason: try container.decode(String.self, forKey: .reason))
        case .action:
            self = .action(
                session: try container.decode(Int.self, forKey: .session),
                windowID: try container.decode(Int.self, forKey: .windowID),
                kind: try container.decode(String.self, forKey: .kind),
                x: try container.decodeIfPresent(Double.self, forKey: .x),
                y: try container.decodeIfPresent(Double.self, forKey: .y)
            )
        case .screenshotTaken:
            self = .screenshotTaken(
                session: try container.decode(Int.self, forKey: .session),
                windowID: try container.decode(Int.self, forKey: .windowID),
                pngBase64: try container.decode(String.self, forKey: .pngBase64),
                width: try container.decode(Int.self, forKey: .width),
                height: try container.decode(Int.self, forKey: .height),
                scale: try container.decode(Double.self, forKey: .scale)
            )
        case .statusChanged:
            self = .statusChanged(session: try container.decode(Int.self, forKey: .session), status: try container.decode(String.self, forKey: .status))
        case .permissions:
            self = .permissions(
                screenRecording: try container.decode(Bool.self, forKey: .screenRecording),
                accessibility: try container.decode(Bool.self, forKey: .accessibility)
            )
        case .stopped:
            self = .stopped(reason: try container.decode(String.self, forKey: .reason), session: try container.decodeIfPresent(Int.self, forKey: .session))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStarted(let session, let harness, let label, let pid):
            try container.encode(Kind.sessionStarted, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(harness, forKey: .harness)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encodeIfPresent(pid, forKey: .pid)
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
            if let x { try container.encode(x, forKey: .x) } else { try container.encodeNil(forKey: .x) }
            if let y { try container.encode(y, forKey: .y) } else { try container.encodeNil(forKey: .y) }
        case .screenshotTaken(let session, let windowID, let pngBase64, let width, let height, let scale):
            try container.encode(Kind.screenshotTaken, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(pngBase64, forKey: .pngBase64)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encode(scale, forKey: .scale)
        case .statusChanged(let session, let status):
            try container.encode(Kind.statusChanged, forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(status, forKey: .status)
        case .permissions(let screenRecording, let accessibility):
            try container.encode(Kind.permissions, forKey: .type)
            try container.encode(screenRecording, forKey: .screenRecording)
            try container.encode(accessibility, forKey: .accessibility)
        case .stopped(let reason, let session):
            try container.encode(Kind.stopped, forKey: .type)
            try container.encode(reason, forKey: .reason)
            if let session { try container.encode(session, forKey: .session) } else { try container.encodeNil(forKey: .session) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, session, harness, label, pid, windowID, app, title, bounds, reason, kind, x, y, pngBase64, width, height, scale, status, screenRecording, accessibility
    }
}
