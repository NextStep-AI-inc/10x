import AppKit
import Foundation
import OmpKit

protocol AgentApplicationResolving: Sendable {
    func resolve(application: String) -> AgentApplication?
}

struct AgentInstalledApplication: Sendable, Equatable {
    let bundleIdentifier: String
    let localizedDisplayName: String?
    let bundleName: String?
}

protocol AgentApplicationCatalog: Sendable {
    func application(bundleIdentifier: String) -> AgentInstalledApplication?
    func installedApplications() -> [AgentInstalledApplication]
}

struct WorkspaceApplicationResolver: AgentApplicationResolving {
    private let catalog: any AgentApplicationCatalog

    init(catalog: any AgentApplicationCatalog = WorkspaceApplicationCatalog()) {
        self.catalog = catalog
    }

    func resolve(application: String) -> AgentApplication? {
        let requestedApplication = application.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedApplication.isEmpty else { return nil }
        if let application = catalog.application(bundleIdentifier: requestedApplication) {
            return dedicatedApplication(for: application)
        }
        for application in catalog.installedApplications() {
            let names = [application.localizedDisplayName, application.bundleName].compactMap { $0 }
            if names.contains(where: { matches($0, requestedApplication) }) {
                return dedicatedApplication(for: application)
            }
        }
        return nil
    }

    private func dedicatedApplication(for application: AgentInstalledApplication) -> AgentApplication {
        AgentApplication(bundleIdentifier: application.bundleIdentifier, strategy: .newInstance)
    }

    private func matches(_ name: String, _ requestedApplication: String) -> Bool {
        name.compare(
            requestedApplication,
            options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

struct WorkspaceApplicationCatalog: AgentApplicationCatalog {
    private let applicationDirectories: [URL]

    init(applicationDirectories: [URL] = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask)) {
        self.applicationDirectories = applicationDirectories
    }

    func application(bundleIdentifier: String) -> AgentInstalledApplication? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return installedApplication(at: url)
    }

    func installedApplications() -> [AgentInstalledApplication] {
        applicationDirectories
            .flatMap(applicationURLs(in:))
            .compactMap(installedApplication(at:))
    }

    private func applicationURLs(in directory: URL) -> [URL] {
        var pendingDirectories = [(directory, 0)]
        var applications: [URL] = []
        while let (currentDirectory, depth) = pendingDirectories.popLast() {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: currentDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
            else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    applications.append(child)
                } else if depth < 2,
                          (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    pendingDirectories.append((child, depth + 1))
                }
            }
        }
        return applications
    }

    private func installedApplication(at url: URL) -> AgentInstalledApplication? {
        guard let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }
        return AgentInstalledApplication(
            bundleIdentifier: bundleIdentifier,
            localizedDisplayName: localizedValue(for: "CFBundleDisplayName", in: bundle),
            bundleName: localizedValue(for: "CFBundleName", in: bundle))
    }

    private func localizedValue(for key: String, in bundle: Bundle) -> String? {
        (bundle.localizedInfoDictionary?[key] as? String)
            ?? (bundle.infoDictionary?[key] as? String)
    }
}

struct AgentDesktopHostToolOutcome: Sendable, Equatable {
    let result: JSONValue
    let isError: Bool
    let manifest: AgentDesktopManifest
}

actor AgentDesktopHostTool {
    static let definition = HostToolDefinition(
        name: "agent_desktop",
        description: "Launch a dedicated app window before using computer. Prefer launch. Borrow an existing window only when the user's request explicitly requires its current authenticated or stateful contents.",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object(["enum": .array([.string("launch"), .string("borrow")])]),
                "application": .object(["type": .string("string")]),
                "windowId": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(false),
        ]))

    private let coordinator: AgentDesktopCoordinator
    private let launcher: (any DedicatedWindowLaunching)?
    private let applicationResolver: any AgentApplicationResolving
    private var launchTasks: [String: Task<WindowLaunchResult, Error>] = [:]
    private var cancelledCallIDs: Set<String> = []

    init(
        coordinator: AgentDesktopCoordinator,
        launcher: (any DedicatedWindowLaunching)? = nil,
        applicationResolver: any AgentApplicationResolving = WorkspaceApplicationResolver()
    ) {
        self.coordinator = coordinator
        self.launcher = launcher
        self.applicationResolver = applicationResolver
    }

    func handle(
        _ call: HostToolCall,
        in desktop: PreparedAgentDesktop,
        manifest: AgentDesktopManifest
    ) async -> AgentDesktopHostToolOutcome {
        guard call.name == Self.definition.name else {
            return failure("Unknown host tool", manifest: manifest)
        }
        guard !cancelledCallIDs.contains(call.id) else {
            return failure("Launch cancelled", manifest: manifest)
        }
        guard let action = call.arguments["action"]?.stringValue else {
            return failure("Invalid request", manifest: manifest)
        }

        switch action {
        case "borrow":
            return await borrow(call: call, desktop: desktop, manifest: manifest)
        case "launch":
            return await launch(call: call, desktop: desktop, manifest: manifest)
        default:
            return failure("Invalid request", manifest: manifest)
        }
    }

    func cancel(callID: String) {
        cancelledCallIDs.insert(callID)
        launchTasks[callID]?.cancel()
    }

    private func borrow(
        call: HostToolCall,
        desktop: PreparedAgentDesktop,
        manifest: AgentDesktopManifest
    ) async -> AgentDesktopHostToolOutcome {
        guard let windowID = call.arguments["windowId"]?.stringValue else {
            return failure("Invalid request", manifest: manifest)
        }
        do {
            guard let window = try await coordinator.listWindows(in: desktop).first(where: { $0.id == windowID }) else {
                return failure("Window unavailable", manifest: manifest)
            }
            guard !cancelledCallIDs.contains(call.id) else {
                return failure("Launch cancelled", manifest: manifest)
            }
            var updatedManifest = manifest
            updatedManifest.borrow(windowID: window.id)
            return success(applicationName: window.app, windowIDs: [window.id], manifest: updatedManifest)
        } catch {
            return failure("Window unavailable", manifest: manifest)
        }
    }

    private func launch(
        call: HostToolCall,
        desktop: PreparedAgentDesktop,
        manifest: AgentDesktopManifest
    ) async -> AgentDesktopHostToolOutcome {
        guard let requestedApplication = call.arguments["application"]?.stringValue,
              let application = applicationResolver.resolve(application: requestedApplication)
        else { return failure("Application unavailable", manifest: manifest) }

        let task: Task<WindowLaunchResult, Error>
        if let launcher {
            task = Task { try await launcher.launch(application, in: desktop) }
        } else {
            let coordinator = coordinator
            task = Task {
                let launcher = try coordinator.dedicatedWindowLauncher(for: desktop)
                return try await launcher.launch(application, in: desktop)
            }
        }
        launchTasks[call.id] = task
        defer { launchTasks.removeValue(forKey: call.id) }

        do {
            let launchResult = try await task.value
            var updatedManifest = manifest
            updatedManifest.claim(launchResult)
            guard !cancelledCallIDs.contains(call.id) else {
                return failure("Launch cancelled", manifest: updatedManifest)
            }
            let applicationName = launchResult.ownedWindows.first?.applicationName ?? "Application"
            return success(
                applicationName: applicationName,
                windowIDs: launchResult.ownedWindows.map(\.id),
                manifest: updatedManifest)
        } catch DedicatedWindowLaunchError.ambiguousNewWindows {
            guard !cancelledCallIDs.contains(call.id) else {
                return failure("Launch cancelled", manifest: manifest)
            }
            var updatedManifest = manifest
            updatedManifest.recordAmbiguous(application: sanitizedApplicationName(requestedApplication))
            return failure("Ambiguous launch", manifest: updatedManifest)
        } catch is CancellationError {
            return failure("Launch cancelled", manifest: manifest)
        } catch {
            guard !cancelledCallIDs.contains(call.id) else {
                return failure("Launch cancelled", manifest: manifest)
            }
            return failure("Launch failed", manifest: manifest)
        }
    }

    private func success(
        applicationName: String,
        windowIDs: [String],
        manifest: AgentDesktopManifest
    ) -> AgentDesktopHostToolOutcome {
        let name = sanitizedApplicationName(applicationName)
        return AgentDesktopHostToolOutcome(
            result: textResult("\(name): \(windowIDs.joined(separator: ", "))"),
            isError: false,
            manifest: manifest)
    }

    private func failure(
        _ description: String,
        manifest: AgentDesktopManifest
    ) -> AgentDesktopHostToolOutcome {
        AgentDesktopHostToolOutcome(
            result: textResult("[AgentDesktopHostTool:handle] \(description) — {request: sanitized}"),
            isError: true,
            manifest: manifest)
    }

    private func textResult(_ text: String) -> JSONValue {
        .object([
            "content": .array([
                .object(["type": .string("text"), "text": .string(text)]),
            ]),
        ])
    }

    private func sanitizedApplicationName(_ name: String) -> String {
        let leaf = name.split(separator: "/").last.map(String.init) ?? "Application"
        let allowed = leaf.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || CharacterSet.whitespaces.contains($0)
                || "._-".unicodeScalars.contains($0)
        }
        let sanitized = String(String.UnicodeScalarView(allowed)).prefix(64)
        return sanitized.isEmpty ? "Application" : String(sanitized)
    }
}
