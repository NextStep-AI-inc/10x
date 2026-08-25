import Foundation
import Observation

@MainActor
@Observable
final class RailExpansionModel {
    private(set) var isExpanded = false

    @ObservationIgnored private let collapseDelay: Duration
    @ObservationIgnored private var isPointerInside = false
    @ObservationIgnored private var hasKeyboardFocus = false
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    init(collapseDelay: Duration = .milliseconds(300)) {
        self.collapseDelay = collapseDelay
    }

    func pointerEntered() {
        isPointerInside = true
        collapseTask?.cancel()
        isExpanded = true
    }

    func pointerExited() {
        isPointerInside = false
        scheduleCollapse()
    }

    func focusChanged(_ hasFocus: Bool) {
        hasKeyboardFocus = hasFocus
        if hasFocus {
            collapseTask?.cancel()
            isExpanded = true
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard !isPointerInside, !hasKeyboardFocus else { return }
        let delay = collapseDelay
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.collapseIfOutside()
        }
    }

    private func collapseIfOutside() {
        guard !isPointerInside, !hasKeyboardFocus else { return }
        isExpanded = false
    }
}
