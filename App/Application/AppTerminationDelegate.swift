import AppKit

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    typealias Sleep = @Sendable (Duration) async throws -> Void
    typealias Reply = @MainActor @Sendable (NSApplication, Bool) -> Void

    var shutdown: (@MainActor @Sendable () async -> Void)?
    private let terminationGrace: Duration
    private let sleep: Sleep
    private let reply: Reply
    private var isFinishingTermination = false
    private var isShutdownComplete = false

    override convenience init() {
        self.init(
            terminationGrace: .seconds(2),
            sleep: { try await Self.liveSleep(for: $0) },
            reply: { Self.liveReply(application: $0, shouldTerminate: $1) })
    }

    convenience init(reply: @escaping Reply) {
        self.init(
            terminationGrace: .seconds(2),
            sleep: { try await Self.liveSleep(for: $0) },
            reply: reply)
    }

    init(
        terminationGrace: Duration,
        sleep: @escaping Sleep,
        reply: @escaping Reply
    ) {
        self.terminationGrace = terminationGrace
        self.sleep = sleep
        self.reply = reply
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isShutdownComplete else { return .terminateNow }
        guard let shutdown else {
            isShutdownComplete = true
            return .terminateNow
        }
        guard !isFinishingTermination else { return .terminateLater }
        isFinishingTermination = true
        Task { @MainActor in
            let sleep = self.sleep
            let terminationGrace = self.terminationGrace
            let (results, continuation) = AsyncStream<Bool>.makeStream(
                bufferingPolicy: .bufferingNewest(1))
            _ = Task { @MainActor in
                await shutdown()
                continuation.yield(true)
            }
            let timeoutTask = Task {
                try? await sleep(terminationGrace)
                continuation.yield(false)
            }
            var iterator = results.makeAsyncIterator()
            let finishedShutdown = await iterator.next() ?? false
            continuation.finish()
            if finishedShutdown {
                timeoutTask.cancel()
            }
            isShutdownComplete = true
            reply(sender, true)
        }
        return .terminateLater
    }

    private static func liveSleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }

    private static func liveReply(
        application: NSApplication,
        shouldTerminate: Bool
    ) {
        application.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}
