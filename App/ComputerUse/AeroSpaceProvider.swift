import Foundation
import OmpKit

struct AeroSpaceProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind = .aeroSpace
    private let executable: URL
    private let runner: any AgentDesktopCommandRunning

    init(
        executable: URL = URL(filePath: "/opt/homebrew/bin/aerospace"),
        runner: any AgentDesktopCommandRunning = AgentDesktopCommandRunner()
    ) {
        self.executable = executable
        self.runner = runner
    }

    func probe() async -> ProviderProbe {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return unavailable(.missing)
        }
        do {
            _ = try await listWindows()
            return ProviderProbe(
                availability: .healthy,
                integrationVersion: "1.0.0",
                capabilities: .isolated)
        } catch {
            return unavailable(.failed)
        }
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        let workspaceID = try workspaceID(for: sessionToken)
        let result = await probe()
        guard result.availability == .healthy else {
            throw AgentDesktopProviderError.unavailable(kind, result.availability)
        }
        return PreparedAgentDesktop(provider: kind, workspaceID: workspaceID, capabilities: result.capabilities)
    }

    func listWindows() async throws -> [AgentWindow] {
        let output = try await runner.run(
            executable: executable,
            arguments: [
                "list-windows",
                "--all",
                "--format",
                "%{window-id} %{app-name} %{app-pid} %{workspace}",
                "--json",
            ],
            timeout: .seconds(2))
        guard let windows = output.json.arrayValue else {
            throw AgentDesktopProviderError.malformedResponse(kind)
        }
        return try windows.map(parseWindow)
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

    func move(windowID: String, to workspaceID: String) async throws {
        guard Self.isSafeIdentifier(windowID) else { throw AgentDesktopProviderError.invalidWindowIdentifier }
        guard Self.isValidWorkspaceID(workspaceID) else { throw AgentDesktopProviderError.invalidWorkspaceIdentifier }
        _ = try await runner.run(
            executable: executable,
            arguments: ["move-node-to-workspace", "--window-id", windowID, workspaceID],
            timeout: .seconds(2))
    }

    func restore(windowID: String, to workspaceID: String) async throws {
        try await move(windowID: windowID, to: workspaceID)
    }

    func openVisibly(workspaceID: String) async throws {
        guard Self.isValidWorkspaceID(workspaceID) else { throw AgentDesktopProviderError.invalidWorkspaceIdentifier }
        _ = try await runner.run(
            executable: executable,
            arguments: ["workspace", workspaceID],
            timeout: .seconds(2))
    }

    func release(workspaceID: String) async {}

    private func unavailable(_ availability: ProviderAvailability) -> ProviderProbe {
        ProviderProbe(availability: availability, integrationVersion: nil, capabilities: .background)
    }

    private func workspaceID(for sessionToken: String) throws -> String {
        let token = sessionToken.lowercased()
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw AgentDesktopProviderError.invalidSessionToken
        }
        let repeated = String(repeating: token, count: 12 / token.count + 1)
        let workspaceID = "10x-\(repeated.prefix(12))"
        guard Self.isValidWorkspaceID(workspaceID) else {
            throw AgentDesktopProviderError.invalidSessionToken
        }
        return workspaceID
    }

    private func parseWindow(_ value: JSONValue) throws -> AgentWindow {
        guard case .int(let windowID)? = value["window-id"], windowID > 0,
              let app = value["app-name"]?.stringValue,
              !app.isEmpty,
              case .int(let rawProcessID)? = value["app-pid"],
              let processID = Int32(exactly: rawProcessID), processID > 0,
              let workspaceID = value["workspace"]?.stringValue, !workspaceID.isEmpty
        else { throw AgentDesktopProviderError.malformedResponse(kind) }
        return AgentWindow(
            id: String(windowID),
            processID: processID,
            app: app,
            workspaceID: workspaceID)
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func isValidWorkspaceID(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
    }
}
