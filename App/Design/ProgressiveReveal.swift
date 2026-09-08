struct ProgressiveReveal: Equatable, Sendable {
    let initialLimit: Int
    let pageSize: Int
    private(set) var limit: Int

    init(initialLimit: Int, pageSize: Int) {
        precondition(initialLimit > 0 && pageSize > 0)
        self.initialLimit = initialLimit
        self.pageSize = pageSize
        limit = initialLimit
    }

    func visibleCount(total: Int) -> Int {
        min(max(0, total), limit)
    }

    func remainingCount(total: Int) -> Int {
        max(0, total - visibleCount(total: total))
    }

    func nextPageCount(total: Int) -> Int {
        min(pageSize, remainingCount(total: total))
    }

    func canRevealMore(total: Int) -> Bool {
        remainingCount(total: total) > 0
    }

    mutating func revealNextPage(total: Int) {
        limit = visibleCount(total: total) + nextPageCount(total: total)
    }

    mutating func revealAdditional(_ count: Int, total: Int) {
        limit = min(max(0, total), visibleCount(total: total) + max(0, count))
    }

    mutating func collapse() {
        limit = initialLimit
    }
}
