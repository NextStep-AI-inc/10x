import AppKit

@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    var shutdown: (@MainActor @Sendable () async -> Void)?
    private var isFinishingTermination = false
    private var isShutdownComplete = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isShutdownComplete else { return .terminateNow }
        guard !isFinishingTermination else { return .terminateLater }
        isFinishingTermination = true
        Task {
            await shutdown?()
            isShutdownComplete = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
