import Foundation
import Observation
import OSLog
import OmpKit

@MainActor
@Observable
final class SearchModalModel {
    @ObservationIgnored private static let signposter = OSSignposter(
        subsystem: "com.tannerpham.tenx",
        category: .pointsOfInterest)

    var query = "" {
        didSet { scheduleSearch() }
    }
    var filters = Set(SearchResultKind.allCases)
    var selectedResultID: SearchResult.ID?
    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false

    var visibleResults: [SearchResult] {
        results.filter { filters.contains($0.kind) }
    }

    @ObservationIgnored private let service: any SessionSearching
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var sessions: [SessionMetadata]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchRequestID = 0

    init(
        sessions: [SessionMetadata],
        service: any SessionSearching,
        debounce: Duration = .milliseconds(250)
    ) {
        self.sessions = sessions
        self.service = service
        self.debounce = debounce
    }

    deinit {
        searchTask?.cancel()
    }

    func updateSessions(_ sessions: [SessionMetadata]) {
        self.sessions = sessions
        scheduleSearch()
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchRequestID += 1
        isSearching = false
    }

    func toggle(_ kind: SearchResultKind) {
        if filters == [kind] {
            filters = Set(SearchResultKind.allCases)
        } else {
            filters = [kind]
        }
        selectFirstVisibleResult()
    }

    func select(_ result: SearchResult) {
        selectedResultID = result.id
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchRequestID += 1
        let requestID = searchRequestID
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            selectedResultID = nil
            isSearching = false
            return
        }

        let sessions = sessions
        let debounce = debounce
        isSearching = true
        searchTask = Task { [weak self, service] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            guard !Task.isCancelled, self?.isCurrentSearchRequest(requestID) == true else { return }
            Self.signposter.emitEvent("SearchQueryStarted")
            let matches = await service.search(query: query, sessions: sessions)
            Self.signposter.emitEvent("SearchQueryFinished")
            guard let self, !Task.isCancelled, self.searchRequestID == requestID else { return }
            self.results = matches
            self.isSearching = false
            self.selectFirstVisibleResult()
        }
    }

    private func isCurrentSearchRequest(_ requestID: Int) -> Bool {
        searchRequestID == requestID
    }

    private func selectFirstVisibleResult() {
        guard !visibleResults.contains(where: { $0.id == selectedResultID }) else { return }
        selectedResultID = visibleResults.first?.id
    }
}
