import Foundation
import Observation

typealias OnboardingInstallLogFlushCallback = @MainActor () -> Void
typealias OnboardingInstallLogFlushScheduler = (@escaping OnboardingInstallLogFlushCallback) -> Void

struct OnboardingInstallLogLine: Identifiable, Equatable {
    let id: Int
    let text: String
}

@MainActor
@Observable
final class OnboardingInstallLogBuffer {
    private(set) var totalCount = 0
    private(set) var flushRevision = 0

    @ObservationIgnored private let scheduleFlush: OnboardingInstallLogFlushScheduler?
    @ObservationIgnored private var lines: [String] = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var isFlushScheduled = false
    @ObservationIgnored private var flushGeneration = 0

    init(scheduleFlush: OnboardingInstallLogFlushScheduler? = nil) {
        self.scheduleFlush = scheduleFlush
    }

    func append(_ line: String) {
        lines.append(line)
        scheduleFlushIfNeeded()
    }

    func flush() {
        invalidateScheduledFlush()
        publish()
    }

    func reset() {
        invalidateScheduledFlush()
        lines.removeAll(keepingCapacity: true)
        totalCount = 0
        flushRevision += 1
    }

    func visibleTail(limit: Int) -> [OnboardingInstallLogLine] {
        let visibleCount = min(max(0, limit), totalCount)
        let start = totalCount - visibleCount
        return lines[start..<totalCount].enumerated().map { offset, text in
            OnboardingInstallLogLine(id: start + offset, text: text)
        }
    }

    var completeText: String {
        lines.joined(separator: "\n")
    }

    private func scheduleFlushIfNeeded() {
        guard !isFlushScheduled else { return }

        isFlushScheduled = true
        flushGeneration += 1
        let generation = flushGeneration
        let callback: OnboardingInstallLogFlushCallback = { [weak self] in
            self?.flushIfCurrent(generation: generation)
        }

        if let scheduleFlush {
            scheduleFlush(callback)
        } else {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.flushIfCurrent(generation: generation)
            }
        }
    }

    private func flushIfCurrent(generation: Int) {
        guard isFlushScheduled, flushGeneration == generation else { return }
        isFlushScheduled = false
        flushTask = nil
        publish()
    }

    private func invalidateScheduledFlush() {
        flushGeneration += 1
        isFlushScheduled = false
        flushTask?.cancel()
        flushTask = nil
    }

    private func publish() {
        totalCount = lines.count
        flushRevision += 1
    }
}
