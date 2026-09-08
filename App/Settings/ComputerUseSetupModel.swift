import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ComputerUseSetupModel {
    static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    let supervision: SupervisionClient
    private let installer: ComputerUseInstaller

    private(set) var isInstalling = false
    private(set) var installLog = ""
    private(set) var isRunningSelfcheck = false
    private(set) var selfcheckOutput = ""

    var isInstalled: Bool { installer.isInstalled }

    init(
        supervision: SupervisionClient,
        installer: ComputerUseInstaller = ComputerUseInstaller()
    ) {
        self.supervision = supervision
        self.installer = installer
    }

    func openScreenRecordingSettings() {
        NSWorkspace.shared.open(Self.screenRecordingSettingsURL)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    func installOrReinstall() async {
        guard !isInstalling else { return }
        isInstalling = true
        installLog = ""
        defer { isInstalling = false }

        guard let scriptURL = Self.locateInstallScript() else {
            installLog = "[ComputerUse:Setup] install script not found"
            return
        }

        do {
            let output = try await Self.runProcess(
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [scriptURL.path],
                timeout: 300)
            installLog = output
            try installer.ensureMounted()
            installLog += "\nMCP mount: updated \(installer.ompConfigPath)"
        } catch {
            installLog = "[ComputerUse:Setup] Install failed — \(error.localizedDescription)"
        }
    }

    func runSelfcheck() async {
        guard !isRunningSelfcheck else { return }
        isRunningSelfcheck = true
        selfcheckOutput = ""
        defer { isRunningSelfcheck = false }

        guard isInstalled else {
            selfcheckOutput = "tenx-computer is not installed"
            return
        }

        do {
            selfcheckOutput = try await Self.runProcess(
                executable: URL(fileURLWithPath: installer.binaryPath),
                arguments: ["selfcheck"],
                timeout: 30)
        } catch {
            selfcheckOutput = "[ComputerUse:Setup] Selfcheck failed — \(error.localizedDescription)"
        }
    }

    private static func locateInstallScript() -> URL? {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let script = url.appendingPathComponent("scripts/install_computer.sh")
            if FileManager.default.fileExists(atPath: script.path) { return script }
        }
        return nil
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let output = Pipe()
                let error = Pipe()
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = error

                let group = DispatchGroup()
                group.enter()
                process.terminationHandler = { _ in group.leave() }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timedOut = group.wait(timeout: .now() + timeout) == .timedOut
                if timedOut {
                    process.terminate()
                    continuation.resume(throwing: ProcessRunError.timedOut)
                    return
                }

                let stdout = String(decoding: (try? output.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
                let stderr = String(decoding: (try? error.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
                let combined = [stdout, stderr]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                if process.terminationStatus == 0 {
                    continuation.resume(returning: combined.isEmpty ? "OK" : combined)
                } else {
                    continuation.resume(throwing: ProcessRunError.nonzeroExit(
                        process.terminationStatus,
                        combined.isEmpty ? "exit \(process.terminationStatus)" : combined))
                }
            }
        }
    }
}

private enum ProcessRunError: LocalizedError {
    case timedOut
    case nonzeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .timedOut: "timed out"
        case .nonzeroExit(let code, let message): "exit \(code): \(message)"
        }
    }
}
