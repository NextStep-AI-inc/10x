import Foundation
import Observation
import OmpKit

@MainActor
@Observable
final class SearchModalModel {
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

    @ObservationIgnored private let service: SessionSearchService
    @ObservationIgnored private var sessions: [SessionMetadata]
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        sessions: [SessionMetadata],
        service: SessionSearchService = SessionSearchService()
    ) {
        self.sessions = sessions
        self.service = service
    }

    func updateSessions(_ sessions: [SessionMetadata]) {
        self.sessions = sessions
        scheduleSearch()
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
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            selectedResultID = nil
            isSearching = false
            return
        }

        let query = query
        let sessions = sessions
        isSearching = true
        searchTask = Task { [weak self, service] in
            let matches = await service.search(query: query, sessions: sessions)
            guard let self, !Task.isCancelled else { return }
            self.results = matches
            self.isSearching = false
            self.selectFirstVisibleResult()
        }
    }

    private func selectFirstVisibleResult() {
        guard !visibleResults.contains(where: { $0.id == selectedResultID }) else { return }
        selectedResultID = visibleResults.first?.id
    }
}
