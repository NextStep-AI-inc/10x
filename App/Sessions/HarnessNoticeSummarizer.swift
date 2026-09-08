import CryptoKit
import Foundation

protocol HarnessNoticeSummarizing: Sendable {
    /// One-line summary, or nil when no model is configured or the run fails —
    /// the caller then keeps the static notice text.
    func summarize(_ descriptor: HarnessMessageDescriptor) async -> String?
}

actor HarnessNoticeSummarizer: HarnessNoticeSummarizing {
    private let resolveModel: @Sendable () async -> String?
    private let run: @Sendable ([String]) async throws -> Data
    private let cacheURL: URL
    private var cache: [String: String]?
    private static let promptLimit = 8_000

    init(
        resolveModel: @escaping @Sendable () async -> String?,
        cacheURL: URL,
        run: @escaping @Sendable ([String]) async throws -> Data
    ) {
        self.resolveModel = resolveModel
        self.cacheURL = cacheURL
        self.run = run
    }

    static func defaultCacheURL() -> URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "10x", directoryHint: .isDirectory)
            .appending(path: "harness-summaries.json")
    }

    func summarize(_ descriptor: HarnessMessageDescriptor) async -> String? {
        let key = SHA256.hash(data: Data(descriptor.text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        if let cached = cachedSummaries()[key] { return cached }
        guard let model = await resolveModel() else { return nil }
        if let cached = cache?[key] { return cached }
        let prompt = """
            Summarize in one short sentence, for the user of a chat UI, what \
            this hidden harness message says. Plain text, no markup, 120 \
            characters max.

            \(descriptor.text.prefix(Self.promptLimit))
            """
        // omp -p self-terminates after answering; a hung child just leaves the
        // static notice. ponytail ceiling: no timeout — upgrade path is a
        // task-group race with a 60 s cap.
        guard let data = try? await run([
                "-p", "--model", model, "--no-session", "--no-tools", prompt])
        else { return nil }
        if let cached = cache?[key] { return cached }
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let summary = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty })
        guard let summary else { return nil }
        cache?[key] = summary
        persist()
        return summary
    }

    private func cachedSummaries() -> [String: String] {
        if let cache { return cache }
        let loaded = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache = loaded
        return loaded
    }

    private func persist() {
        guard let cache,
              let data = try? JSONEncoder().encode(cache)
        else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
