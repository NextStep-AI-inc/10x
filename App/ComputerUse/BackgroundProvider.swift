import CoreGraphics
import Foundation

struct BackgroundProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind = .background

    func probe() async -> ProviderProbe {
        ProviderProbe(availability: .healthy, integrationVersion: nil, capabilities: .background)
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        PreparedAgentDesktop(provider: kind, workspaceID: nil, capabilities: .background)
    }

    func listWindows() async throws -> [AgentWindow] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return rawWindows.compactMap { window in
            guard let number = window[kCGWindowNumber as String] as? NSNumber,
                  let process = window[kCGWindowOwnerPID as String] as? NSNumber,
                  let app = window[kCGWindowOwnerName as String] as? String,
                  !app.isEmpty
            else { return nil }
            return AgentWindow(id: number.stringValue, processID: process.int32Value, app: app, workspaceID: nil)
        }
    }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        AsyncStream { continuation in
            let task = Task {
                var previous = Set((try? await listWindows()) ?? [])
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    let current = Set((try? await listWindows()) ?? [])
                    for window in current.subtracting(previous) { continuation.yield(.appeared(window)) }
                    for window in previous.subtracting(current) { continuation.yield(.disappeared(id: window.id)) }
                    previous = current
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func move(windowID: String, to workspaceID: String) async throws {}
    func restore(windowID: String, to workspaceID: String) async throws {}
    func openVisibly(workspaceID: String) async throws {}
    func release(workspaceID: String) async {}
}
