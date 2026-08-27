import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func rapidQueryChangesDispatchOnlyTheFinalSearch() async throws {
    let spy = SearchSpy()
    let model = SearchModalModel(
        sessions: [searchMetadata(path: "/tmp/final.jsonl")],
        service: spy,
        debounce: .milliseconds(10))

    for prefix in searchPrefixes() {
        model.query = prefix
    }
    try await spy.waitForQueryCount(1)
    try await waitForResultTitles(["Result for performance"], in: model)

    #expect(await spy.queries == [try #require(searchPrefixes().last)])
    #expect(model.results.map(\.title) == ["Result for performance"])
}

@MainActor
@Test func clearingQueryCancelsPendingSearch() async throws {
    let spy = SearchSpy()
    let model = SearchModalModel(
        sessions: [searchMetadata(path: "/tmp/cancel.jsonl")],
        service: spy,
        debounce: .milliseconds(30))

    model.query = "pending"
    model.query = "   "
    try await Task.sleep(for: .milliseconds(80))

    #expect(await spy.queries.isEmpty)
    #expect(model.results.isEmpty)
    #expect(model.selectedResultID == nil)
    #expect(!model.isSearching)
}

@MainActor
@Test func cancellingModelBeforeDebounceDispatchesNoSearch() async throws {
    let spy = SearchSpy()
    let model = SearchModalModel(
        sessions: [searchMetadata(path: "/tmp/dismissed.jsonl")],
        service: spy,
        debounce: .milliseconds(30))

    model.query = "dismissed"
    model.cancelSearch()
    try await Task.sleep(for: .milliseconds(80))

    #expect(await spy.queries.isEmpty)
    #expect(!model.isSearching)
}

@MainActor
@Test func staleSearchCannotReplaceCurrentResults() async throws {
    let spy = SearchSpy(delayedQueries: ["first"])
    let model = SearchModalModel(
        sessions: [searchMetadata(path: "/tmp/stale.jsonl")],
        service: spy,
        debounce: .milliseconds(1))

    model.query = "first"
    try await spy.waitForQueryCount(1)
    model.query = "second"
    try await spy.waitForQueryCount(2)
    try await Task.sleep(for: .milliseconds(30))

    #expect(model.results.map(\.title) == ["Result for second"])

    await spy.finishDelayedQuery("first")
    try await Task.sleep(for: .milliseconds(30))

    #expect(model.results.map(\.title) == ["Result for second"])
}

private actor SearchSpy: SessionSearching {
    private var recordedQueries: [String] = []
    private var delayedQueries: Set<String>
    private var continuations: [String: CheckedContinuation<[SearchResult], Never>] = [:]

    init(delayedQueries: Set<String> = []) {
        self.delayedQueries = delayedQueries
    }

    var queries: [String] {
        recordedQueries
    }

    func search(query: String, sessions: [SessionMetadata]) async -> [SearchResult] {
        recordedQueries.append(query)
        if delayedQueries.remove(query) != nil {
            return await withCheckedContinuation { continuation in
                continuations[query] = continuation
            }
        }
        return [result(for: query)]
    }

    func waitForQueryCount(_ count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while ContinuousClock.now < deadline, recordedQueries.count < count {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func finishDelayedQuery(_ query: String) {
        continuations.removeValue(forKey: query)?.resume(returning: [result(for: query)])
    }

    private func result(for query: String) -> SearchResult {
        SearchResult(
            sessionPath: "/tmp/\(query).jsonl",
            entryID: nil,
            projectPath: "/tmp/Prime Radiant",
            title: "Result for \(query)",
            excerpt: query,
            kind: .session)
    }
}

private func searchPrefixes() -> [String] {
    let query = "performance"
    return (1...22).map { length in
        String(query.prefix(min(length, query.count)))
    }
}

private func searchMetadata(path: String) -> SessionMetadata {
    SessionMetadata(
        path: path,
        sessionId: path,
        cwd: "/tmp/Prime Radiant",
        title: "Search fixture",
        created: Date(timeIntervalSince1970: 10),
        modified: Date(timeIntervalSince1970: 10),
        sizeBytes: 10,
        status: .complete)
}

@MainActor
private func waitForResultTitles(
    _ titles: [String],
    in model: SearchModalModel
) async throws {
    await waitUntil("the search results to settle") {
        model.results.map(\.title) == titles
    }
}
