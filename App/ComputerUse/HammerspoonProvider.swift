import Foundation
import OmpKit

struct HammerspoonProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind = .hammerspoon
    private let executable: URL
    private let runner: any AgentDesktopCommandRunning
    private let watcherPollInterval: Duration

    init(
        executable: URL = URL(filePath: "/usr/local/bin/hs"),
        runner: any AgentDesktopCommandRunning = AgentDesktopCommandRunner(),
        watcherPollInterval: Duration = .seconds(1)
    ) {
        self.executable = executable
        self.runner = runner
        self.watcherPollInterval = watcherPollInterval
    }

    func probe() async -> ProviderProbe {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return unavailable(.missing)
        }
        do {
            let value = try await invoke("return hs.json.encode(tenx.probe())")
            guard let version = value["integrationVersion"]?.stringValue,
                  version.split(separator: ".").first == "1",
                  let capabilities = parseCapabilities(value["capabilities"]),
                  let workspaceID = value["workspaceID"]?.stringValue,
                  Self.isPositiveDecimalIdentifier(workspaceID)
            else { return unavailable(.incompatible) }
            return ProviderProbe(availability: .healthy, integrationVersion: version, capabilities: capabilities)
        } catch {
            return unavailable(.failed)
        }
    }

    func prepare(sessionToken: String) async throws -> PreparedAgentDesktop {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw AgentDesktopProviderError.unavailable(kind, .missing)
        }
        do {
            let value = try await invoke("return hs.json.encode(tenx.probe())")
            guard let version = value["integrationVersion"]?.stringValue,
                  version.split(separator: ".").first == "1",
                  let capabilities = parseCapabilities(value["capabilities"]),
                  let workspaceID = value["workspaceID"]?.stringValue,
                  Self.isPositiveDecimalIdentifier(workspaceID)
            else { throw AgentDesktopProviderError.unavailable(kind, .incompatible) }
            return PreparedAgentDesktop(provider: kind, workspaceID: workspaceID, capabilities: capabilities)
        } catch let error as AgentDesktopProviderError {
            throw error
        } catch {
            throw AgentDesktopProviderError.unavailable(kind, .failed)
        }
    }

    func listWindows() async throws -> [AgentWindow] {
        let value = try await invoke("return hs.json.encode(tenx.listWindows())")
        guard let values = value.arrayValue else { throw AgentDesktopProviderError.malformedResponse(kind) }
        return try values.map(parseWindow)
    }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        do {
            try requireSuccessfulOperation(
                try await invoke("return hs.json.encode(tenx.startWatcher())"))
        } catch {
            throw typedOperationError(error)
        }
        let initialWindows: Set<AgentWindow>
        do {
            initialWindows = Set(try await listWindows())
        } catch {
            _ = try? await invoke("return hs.json.encode(tenx.stopWatcher())")
            throw typedOperationError(error)
        }
        return AsyncStream { continuation in
            let task = Task {
                var previous = initialWindows
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: watcherPollInterval)
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    do {
                        let current = Set(try await listWindows())
                        for window in current.subtracting(previous) { continuation.yield(.appeared(window)) }
                        for window in previous.subtracting(current) { continuation.yield(.disappeared(id: window.id)) }
                        previous = current
                    } catch {
                        guard !Task.isCancelled else { break }
                        continuation.yield(.failed(typedOperationError(error)))
                        break
                    }
                }
                _ = try? await invoke("return hs.json.encode(tenx.stopWatcher())")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func move(windowID: String, to workspaceID: String) async throws {
        try await invokeValidated("moveWindow", windowID: windowID, workspaceID: workspaceID)
    }

    func restore(windowID: String, to workspaceID: String) async throws {
        try await invokeValidated("restoreWindow", windowID: windowID, workspaceID: workspaceID)
    }

    func openVisibly(workspaceID: String) async throws {
        guard Self.isPositiveDecimalIdentifier(workspaceID) else {
            throw AgentDesktopProviderError.invalidWorkspaceIdentifier
        }
        _ = try await fixedInvocation("openSpace", values: ["workspaceID": workspaceID])
    }

    func release(workspaceID: String) async {}

    private func invokeValidated(_ function: String, windowID: String, workspaceID: String) async throws {
        guard Self.isPositiveDecimalIdentifier(windowID) else {
            throw AgentDesktopProviderError.invalidWindowIdentifier
        }
        guard Self.isPositiveDecimalIdentifier(workspaceID) else {
            throw AgentDesktopProviderError.invalidWorkspaceIdentifier
        }
        _ = try await fixedInvocation(function, values: ["windowID": windowID, "workspaceID": workspaceID])
    }

    private func fixedInvocation(_ function: String, values: [String: String]) async throws -> JSONValue {
        let data = try JSONEncoder().encode(values)
        let payload = data.base64EncodedString()
        let invocation: String
        switch function {
        case "moveWindow":
            invocation = "tenx.moveWindow(values.windowID, values.workspaceID)"
        case "restoreWindow":
            invocation = "tenx.restoreWindow(values.windowID, values.workspaceID)"
        case "openSpace":
            invocation = "tenx.openSpace(values.workspaceID)"
        default:
            throw AgentDesktopProviderError.malformedResponse(kind)
        }
        let command = "local values=hs.json.decode(hs.base64.decode('\(payload)')); return hs.json.encode(\(invocation))"
        let result = try await invoke(command)
        try requireSuccessfulOperation(result)
        return result
    }

    private func invoke(_ command: String) async throws -> JSONValue {
        try await runner.run(executable: executable, arguments: ["-c", command], timeout: .seconds(2)).json
    }

    private func parseCapabilities(_ value: JSONValue?) -> ProviderCapabilities? {
        guard let canIsolate = value?["canIsolate"]?.boolValue,
              let canMoveWithoutFocus = value?["canMoveWithoutFocus"]?.boolValue,
              let canCaptureOffscreen = value?["canCaptureOffscreen"]?.boolValue,
              let canInputInBackground = value?["canInputInBackground"]?.boolValue
        else { return nil }
        return ProviderCapabilities(
            canIsolate: canIsolate,
            canMoveWithoutFocus: canMoveWithoutFocus,
            canCaptureOffscreen: canCaptureOffscreen,
            canInputInBackground: canInputInBackground)
    }

    private func unavailable(_ availability: ProviderAvailability) -> ProviderProbe {
        ProviderProbe(availability: availability, integrationVersion: nil, capabilities: .background)
    }

    private func typedOperationError(_ error: any Error) -> AgentDesktopProviderError {
        (error as? AgentDesktopProviderError) ?? .operationFailed(kind)
    }

    private func parseWindow(_ value: JSONValue) throws -> AgentWindow {
        guard let id = value["id"]?.stringValue,
              Self.isPositiveDecimalIdentifier(id),
              case .int(let rawProcessID)? = value["processID"],
              let processID = Int32(exactly: rawProcessID), processID > 0,
              let app = value["app"]?.stringValue, !app.isEmpty
        else { throw AgentDesktopProviderError.malformedResponse(kind) }
        let workspaceID = value["workspaceID"]?.stringValue
        if let workspaceID, !Self.isPositiveDecimalIdentifier(workspaceID) {
            throw AgentDesktopProviderError.malformedResponse(kind)
        }
        return AgentWindow(id: id, processID: processID, app: app, workspaceID: workspaceID)
    }

    private func requireSuccessfulOperation(_ value: JSONValue) throws {
        guard value["ok"]?.boolValue == true else {
            throw AgentDesktopProviderError.operationFailed(kind)
        }
    }

    private static func isPositiveDecimalIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber }), let numericValue = Int64(value) else {
            return false
        }
        return numericValue > 0
    }
}
