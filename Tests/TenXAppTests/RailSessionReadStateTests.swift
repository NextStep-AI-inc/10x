import Testing
@testable import TenXApp

@Suite @MainActor struct RailSessionReadStateTests {
    @Test func backgroundCompletionStaysUnreadUntilAcknowledged() {
        let state = RailSessionReadState()

        state.observe(path: "session", activity: .working, isSelected: false)
        state.observe(path: "session", activity: .completed, isSelected: false)

        #expect(state.indicator(for: "session", activity: .completed) == .completed)

        state.observe(path: "session", activity: .completed, isSelected: true)

        #expect(state.indicator(for: "session", activity: .completed) == .neutral)
    }

    @Test func completionWhileOpenIsAlreadyRead() {
        let state = RailSessionReadState()

        state.observe(path: "session", activity: .working, isSelected: true)
        state.observe(path: "session", activity: .completed, isSelected: true)

        #expect(state.indicator(for: "session", activity: .completed) == .neutral)
    }

    @Test func coldCompletedSessionDoesNotBecomeUnread() {
        let state = RailSessionReadState()

        state.observe(path: "historical", activity: .completed, isSelected: false)

        #expect(state.indicator(for: "historical", activity: .completed) == .neutral)
    }

    @Test func actionableAndLiveStatesKeepTheirIndicators() {
        let state = RailSessionReadState()

        #expect(state.indicator(for: "working", activity: .working) == .working)
        #expect(state.indicator(for: "question", activity: .needsInput) == .needsInput)
        #expect(state.indicator(for: "error", activity: .failed) == .failed)
        #expect(state.indicator(for: "stopped", activity: .stopped) == .neutral)
    }
}
