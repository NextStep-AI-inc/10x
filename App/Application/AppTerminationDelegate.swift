import AppKit

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    typealias Reply = @MainActor @Sendable (NSApplication, Bool) -> Void

    var shutdown: (@MainActor @Sendable () async -> Void)?
    private let reply: Reply
    private var isFinishingTermination = false
    private var isShutdownComplete = false

    override convenience init() {
        self.init(reply: { Self.liveReply(application: $0, shouldTerminate: $1) })
    }

    init(reply: @escaping Reply) {
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
            await shutdown()
            isShutdownComplete = true
            reply(sender, true)
        }
        return .terminateLater
    }

    private static func liveReply(
        application: NSApplication,
        shouldTerminate: Bool
    ) {
        application.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}
