import Foundation
import OmpKit

struct HammerspoonProvider: AgentDesktopProvider {
    let kind: AgentDesktopProviderKind = .hammerspoon
    private let executable: URL
    private let runner: any AgentDesktopCommandRunning

    init(
        executable: URL = URL(filePath: "/usr/local/bin/hs"),
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
            let value = try await invoke("return hs.json.encode(tenx.probe())")
            guard let version = value["integrationVersion"]?.stringValue,
                  version.split(separator: ".").first == "1",
                  let capabilities = parseCapabilities(value["capabilities"]),
                  let workspaceID = value["workspaceID"]?.stringValue,
                  Self.isSafeIdentifier(workspaceID)
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
                  Self.isSafeIdentifier(workspaceID)
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
        return values.compactMap { value in
            guard let id = value["id"]?.stringValue,
                  Self.isSafeIdentifier(id),
                  let processID = value["processID"]?.intValue,
                  let app = value["app"]?.stringValue,
                  !app.isEmpty
            else { return nil }
            return AgentWindow(
                id: id,
                processID: Int32(processID),
                app: app,
                workspaceID: value["workspaceID"]?.stringValue)
        }
    }

    func watchWindows() async throws -> AsyncStream<AgentWindowEvent> {
        _ = try await invoke("return hs.json.encode(tenx.startWatcher())")
        return AsyncStream { continuation in
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
        guard Self.isSafeIdentifier(workspaceID) else { throw AgentDesktopProviderError.invalidWorkspaceIdentifier }
        _ = try await fixedInvocation("openSpace", values: ["workspaceID": workspaceID])
    }

    func release(workspaceID: String) async {}

    private func invokeValidated(_ function: String, windowID: String, workspaceID: String) async throws {
        guard Self.isSafeIdentifier(windowID) else { throw AgentDesktopProviderError.invalidWindowIdentifier }
        guard Self.isSafeIdentifier(workspaceID) else { throw AgentDesktopProviderError.invalidWorkspaceIdentifier }
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
        return try await invoke(command)
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

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }
}
