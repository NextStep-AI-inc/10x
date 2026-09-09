import Foundation

enum ComposerRecoveryOwner: Codable, Equatable, Hashable, Sendable {
    case session(String)
    case project(URL)
    case initial(id: UUID, projectURL: URL)

    var canonicalized: Self {
        switch self {
        case .session(let path):
            return .session(Self.canonicalURL(URL(filePath: path)).path)
        case .project(let url):
            return .project(Self.canonicalURL(url))
        case .initial(let id, let projectURL):
            return .initial(id: id, projectURL: Self.canonicalURL(projectURL))
        }
    }

    var projectURL: URL? {
        switch canonicalized {
        case .project(let url), .initial(_, let url): return url
        case .session: return nil
        }
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

struct ComposerRecoveryDraft: Codable, Equatable, Sendable {
    var text: String
    var attachments: [ComposerAttachment]

    var isEmpty: Bool { text.isEmpty && attachments.isEmpty }
}

struct ComposerRecoveryInFlight: Codable, Equatable, Sendable {
    let id: UUID
    let draft: ComposerRecoveryDraft
    let minimumUserIndex: Int
}

struct ComposerRecoveryRecord: Codable, Equatable, Sendable {
    let owner: ComposerRecoveryOwner
    var draft: ComposerRecoveryDraft
    var inFlight: ComposerRecoveryInFlight?
}

enum ComposerRecoveryRoute: Codable, Equatable, Sendable {
    case session(String)
    case newSession(projectURL: URL)

    var canonicalized: Self {
        switch self {
        case .session(let path):
            guard case .session(let canonical) = ComposerRecoveryOwner.session(path).canonicalized else {
                return self
            }
            return .session(canonical)
        case .newSession(let projectURL):
            guard case .project(let canonical) = ComposerRecoveryOwner.project(projectURL).canonicalized else {
                return self
            }
            return .newSession(projectURL: canonical)
        }
    }
}

@MainActor
final class ComposerRecoveryStore {
    static let fileName = "composer-recovery.plist"
    static let maximumEncodedJPEGBytes = 16_000_000

    fileprivate struct Contents: Codable, Sendable {
        let formatVersion: Int
        var records: [ComposerRecoveryRecord]
        var lastMeaningfulRoute: ComposerRecoveryRoute?
        var revision: UInt64
    }

    private let rootURL: URL?
    private let debounce: Duration
    private let writer: ComposerRecoveryWriter?
    private let flushBarrier: @Sendable () async -> Void
    private var contents: Contents
    private var debounceTask: Task<Void, Never>?
    private(set) var errorMessage: String?

    var allRecords: [ComposerRecoveryRecord] { contents.records }
    var lastMeaningfulRoute: ComposerRecoveryRoute? { contents.lastMeaningfulRoute }

    init(
        rootURL: URL,
        debounce: Duration = .milliseconds(250),
        flushBarrier: @escaping @Sendable () async -> Void = {}
    ) {
        self.rootURL = rootURL
        self.debounce = debounce
        self.flushBarrier = flushBarrier
        writer = ComposerRecoveryWriter(fileURL: rootURL.appending(path: Self.fileName))
        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: rootURL.path)
            let fileURL = rootURL.appending(path: Self.fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                let loaded = try PropertyListDecoder().decode(Contents.self, from: data)
                guard loaded.formatVersion == 1 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                contents = Self.sanitized(loaded)
            } else {
                contents = Contents(formatVersion: 1, records: [], revision: 0)
            }
        } catch {
            contents = Contents(formatVersion: 1, records: [], revision: 0)
            errorMessage = "[ComposerRecoveryStore:load] Could not restore local drafts — \(error.localizedDescription)"
        }
    }

    private init() {
        rootURL = nil
        debounce = .zero
        writer = nil
        flushBarrier = {}
        contents = Contents(formatVersion: 1, records: [], revision: 0)
    }

    static func inMemory() -> ComposerRecoveryStore { ComposerRecoveryStore() }

    static func live(fileManager: FileManager = .default) -> ComposerRecoveryStore {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "TenXApp"
        return ComposerRecoveryStore(
            rootURL: applicationSupport.appending(path: bundleID, directoryHint: .isDirectory))
    }

    func record(for owner: ComposerRecoveryOwner) -> ComposerRecoveryRecord? {
        let owner = owner.canonicalized
        return contents.records.first { $0.owner == owner }
    }

    func initialRecords(for projectURL: URL) -> [ComposerRecoveryRecord] {
        let canonicalProject = ComposerRecoveryOwner.project(projectURL).canonicalized
        return contents.records.filter { record in
            guard case .initial(_, let recordProject) = record.owner,
                  case .project(let project) = canonicalProject
            else { return false }
            return recordProject == project
        }
    }

    func setDraft(_ draft: ComposerRecoveryDraft, for owner: ComposerRecoveryOwner) {
        update(owner: owner) { $0.draft = Self.sanitized(draft) }
    }

    func setInFlight(_ inFlight: ComposerRecoveryInFlight?, for owner: ComposerRecoveryOwner) {
        update(owner: owner) { record in
            record.inFlight = inFlight.map {
                ComposerRecoveryInFlight(
                    id: $0.id,
                    draft: Self.sanitized($0.draft),
                    minimumUserIndex: max(0, $0.minimumUserIndex))
            }
        }
    }

    func remove(_ owner: ComposerRecoveryOwner) {
        let owner = owner.canonicalized
        contents.records.removeAll { $0.owner == owner }
        scheduleWrite()
    }

    func moveRecord(from source: ComposerRecoveryOwner, to destination: ComposerRecoveryOwner) {
        let source = source.canonicalized
        let destination = destination.canonicalized
        guard source != destination,
              let sourceIndex = contents.records.firstIndex(where: { $0.owner == source })
        else { return }
        let sourceRecord = contents.records.remove(at: sourceIndex)
        if let destinationIndex = contents.records.firstIndex(where: { $0.owner == destination }) {
            let destinationRecord = contents.records[destinationIndex]
            contents.records[destinationIndex] = ComposerRecoveryRecord(
                owner: destination,
                draft: Self.merged(sourceRecord.draft, destinationRecord.draft),
                inFlight: sourceRecord.inFlight ?? destinationRecord.inFlight)
        } else {
            contents.records.append(ComposerRecoveryRecord(
                owner: destination,
                draft: sourceRecord.draft,
                inFlight: sourceRecord.inFlight))
        }
        scheduleWrite()
    }

    func consumeInitialRecords(for projectURL: URL) -> ComposerRecoveryDraft? {
        let records = initialRecords(for: projectURL)
        guard !records.isEmpty else { return nil }
        let empty = ComposerRecoveryDraft(text: "", attachments: [])
        let draft = records.reduce(empty) { result, record in
            Self.merged(result, Self.merged(record.inFlight?.draft ?? empty, record.draft))
        }
        let owners = Set(records.map(\.owner))
        contents.records.removeAll { owners.contains($0.owner) }
        scheduleWrite()
        return draft
    }

    func setLastMeaningfulRoute(_ route: ComposerRecoveryRoute?) {
        contents.lastMeaningfulRoute = route?.canonicalized
        scheduleWrite()
    }

    @discardableResult
    func flush() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        guard let writer else {
            errorMessage = nil
            return true
        }
        let snapshot = contents
        await flushBarrier()
        let result = await writer.write(snapshot)
        errorMessage = result
        return result == nil
    }

    private func update(
        owner: ComposerRecoveryOwner,
        mutation: (inout ComposerRecoveryRecord) -> Void
    ) {
        let owner = owner.canonicalized
        if let index = contents.records.firstIndex(where: { $0.owner == owner }) {
            mutation(&contents.records[index])
        } else {
            var record = ComposerRecoveryRecord(
                owner: owner,
                draft: ComposerRecoveryDraft(text: "", attachments: []),
                inFlight: nil)
            mutation(&record)
            contents.records.append(record)
        }
        scheduleWrite()
    }

    private func scheduleWrite() {
        contents.revision &+= 1
        guard let writer else { return }
        let snapshot = contents
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.debounce ?? .zero)
                guard !Task.isCancelled else { return }
                let result = await writer.write(snapshot)
                self?.errorMessage = result
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = "[ComposerRecoveryStore:write] Could not save local drafts — \(error.localizedDescription)"
            }
        }
    }

    private static func sanitized(_ contents: Contents) -> Contents {
        var seen: Set<ComposerRecoveryOwner> = []
        let records = contents.records.compactMap { record -> ComposerRecoveryRecord? in
            let owner = record.owner.canonicalized
            guard seen.insert(owner).inserted else { return nil }
            return ComposerRecoveryRecord(
                owner: owner,
                draft: sanitized(record.draft),
                inFlight: record.inFlight.map {
                    ComposerRecoveryInFlight(
                        id: $0.id,
                        draft: sanitized($0.draft),
                        minimumUserIndex: max(0, $0.minimumUserIndex))
                })
        }
        return Contents(
            formatVersion: 1,
            records: records,
            lastMeaningfulRoute: contents.lastMeaningfulRoute?.canonicalized,
            revision: contents.revision)
    }

    private static func sanitized(_ draft: ComposerRecoveryDraft) -> ComposerRecoveryDraft {
        var ids: Set<UUID> = []
        let attachments = draft.attachments.filter { attachment in
            let maximumBytes = attachment.mimeType == "image/png"
                ? ComposerAttachmentEncoder.pngBudgetBytes
                : Self.maximumEncodedJPEGBytes
            guard ids.insert(attachment.id).inserted,
                  !attachment.data.isEmpty,
                  attachment.data.count <= maximumBytes,
                  attachment.pixelWidth > 0,
                  attachment.pixelHeight > 0,
                  attachment.pixelWidth <= ComposerAttachmentEncoder.maxPixelDimension,
                  attachment.pixelHeight <= ComposerAttachmentEncoder.maxPixelDimension,
                  attachment.mimeType == "image/png" || attachment.mimeType == "image/jpeg"
            else { return false }
            return true
        }
        return ComposerRecoveryDraft(text: draft.text, attachments: attachments)
    }

    static func merged(
        _ older: ComposerRecoveryDraft,
        _ newer: ComposerRecoveryDraft
    ) -> ComposerRecoveryDraft {
        let text = [older.text, newer.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        var ids: Set<UUID> = []
        let attachments = (older.attachments + newer.attachments).filter {
            ids.insert($0.id).inserted
        }
        return sanitized(ComposerRecoveryDraft(text: text, attachments: attachments))
    }
}

private actor ComposerRecoveryWriter {
    private let fileURL: URL
    private var latestRevision: UInt64 = 0

    init(fileURL: URL) { self.fileURL = fileURL }

    func write(_ contents: ComposerRecoveryStore.Contents) -> String? {
        guard contents.revision >= latestRevision else { return nil }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(contents)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path)
            latestRevision = contents.revision
            return nil
        } catch {
            return "[ComposerRecoveryStore:write] Could not save local drafts — \(error.localizedDescription)"
        }
    }
}
