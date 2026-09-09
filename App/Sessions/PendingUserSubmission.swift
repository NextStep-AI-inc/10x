import Foundation
import OmpKit

@MainActor
final class SubmissionPresentationStore {
    static let defaultKeyPrefix = "submission-presentation-modes"

    private let defaults: UserDefaults?
    private let keyPrefix: String
    private var memory: [String: [String: String]] = [:]

    init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = SubmissionPresentationStore.defaultKeyPrefix
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    private init() {
        defaults = nil
        keyPrefix = Self.defaultKeyPrefix
    }

    static func inMemory() -> SubmissionPresentationStore {
        SubmissionPresentationStore()
    }

    static func live() -> SubmissionPresentationStore {
        SubmissionPresentationStore(defaults: .standard)
    }

    func mode(forMessageID messageID: String, sessionPath: String) -> StreamingBehavior? {
        guard !messageID.isEmpty else { return nil }
        return modes(forSessionPath: sessionPath)[messageID]
    }

    func modes(forSessionPath sessionPath: String) -> [String: StreamingBehavior] {
        modesByMessageID(sessionPath: sessionPath).compactMapValues {
            StreamingBehavior(rawValue: $0)
        }
    }

    func setMode(
        _ mode: StreamingBehavior,
        forMessageID messageID: String,
        sessionPath: String
    ) {
        guard !messageID.isEmpty else { return }
        let path = Self.canonicalPath(sessionPath)
        var modes = modesByMessageID(sessionPath: path)
        modes[messageID] = mode.rawValue
        if let defaults {
            defaults.set(modes, forKey: defaultsKey(sessionPath: path))
        } else {
            memory[path] = modes
        }
    }

    private func modesByMessageID(sessionPath: String) -> [String: String] {
        let path = Self.canonicalPath(sessionPath)
        if let defaults {
            return defaults.dictionary(forKey: defaultsKey(sessionPath: path))?
                .compactMapValues { $0 as? String } ?? [:]
        }
        return memory[path] ?? [:]
    }

    private func defaultsKey(sessionPath: String) -> String {
        let encodedPath = Data(sessionPath.utf8).base64EncodedString()
        return "\(keyPrefix).\(encodedPath)"
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

struct PendingUserSubmission: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case starting
        case sending
        case queued(StreamingBehavior)
        case unconfirmed

        var label: String {
            switch self {
            case .starting: "Starting session…"
            case .sending: "Sending…"
            case .queued(.steer): "Queued to steer"
            case .queued(.followUp): "Queued as follow-up"
            case .unconfirmed: "Delivery not confirmed. Review before retrying."
            }
        }
    }

    let id: String
    let message: TranscriptMessage
    let minimumUserIndex: Int
    let mode: StreamingBehavior?
    var state: State
    fileprivate var isModeAmbiguous = false
    fileprivate var observedEchoTimestamp: Date?

    init(
        text: String,
        attachments: [ComposerAttachment],
        minimumUserIndex: Int,
        mode: StreamingBehavior? = nil,
        state: State
    ) {
        id = "pending-\(UUID().uuidString)"
        self.minimumUserIndex = minimumUserIndex
        self.mode = mode
        self.state = state
        let images: [JSONValue] = attachments.map { attachment in
            .object(["type": .string("image"), "data": .string(attachment.data.base64EncodedString()),
                     "mimeType": .string(attachment.mimeType)])
        }
        message = TranscriptMessage(id: id, raw: .object([
            "role": .string("user"),
            "content": .array([.object(["type": .string("text"), "text": .string(text)])] + images),
        ]), timestamp: Date(), isFinal: true)
    }

    func matches(_ echo: TranscriptMessage) -> Bool {
        guard echo.role == .user, echo.document.images == message.document.images else { return false }
        if echo.visibleText == message.visibleText { return true }
        if let advisory = TranscriptMessage.advisoryContent(from: echo.raw) {
            return advisory.message == message.visibleText
        }
        // OMP can append structured advice to the user input before publishing
        // its echo. Only recognize that explicit suffix, not arbitrary prefixes.
        guard !message.visibleText.isEmpty, echo.visibleText.hasPrefix(message.visibleText) else { return false }
        let suffix = echo.visibleText.dropFirst(message.visibleText.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.hasPrefix("<advisory ")
    }

    static func reconcile(
        _ pending: [Self],
        messages: [TranscriptMessage],
        consumedIndices: inout Set<Int>,
        matchingObservedTimestamps: Bool = false,
        onMatch: ((Match) -> Void)? = nil
    ) -> [Self] {
        var remaining = pending
        for (index, message) in messages.enumerated() where !consumedIndices.contains(index) {
            let candidates = remaining.indices.filter { candidate in
                let submission = remaining[candidate]
                guard index >= submission.minimumUserIndex,
                      submission.matches(message)
                else { return false }
                guard matchingObservedTimestamps,
                      let timestamp = submission.observedEchoTimestamp
                else { return true }
                return timestamp == message.timestamp
            }
            guard let match = candidates.first else { continue }
            let hasConflictingModes = candidates.dropFirst().contains {
                remaining[$0].mode != remaining[match].mode
            }
            let hasPriorAmbiguity = candidates.contains { remaining[$0].isModeAmbiguous }
            if hasConflictingModes || hasPriorAmbiguity {
                // ponytail: OMP exposes no stable identity for queued inputs. Keep conflicting
                // overlapping duplicates unknown until the runtime supplies one.
                for candidate in candidates {
                    remaining[candidate].isModeAmbiguous = true
                }
            }
            consumedIndices.insert(index)
            var submission = remaining.remove(at: match)
            if submission.observedEchoTimestamp == nil {
                submission.observedEchoTimestamp = message.timestamp
            }
            onMatch?(Match(submission: submission, message: message, messageIndex: index))
        }
        let minimum = remaining.map(\.minimumUserIndex).min() ?? messages.count
        consumedIndices = consumedIndices.filter { $0 >= minimum }
        return remaining
    }

    struct Match {
        let submission: PendingUserSubmission
        let message: TranscriptMessage
        let messageIndex: Int

        var mode: StreamingBehavior? {
            submission.isModeAmbiguous ? nil : submission.mode
        }
    }
}
