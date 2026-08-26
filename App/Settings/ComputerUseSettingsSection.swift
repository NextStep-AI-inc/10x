import SwiftUI
import OmpKit

struct ComputerUseSettingsSection: View {
    let model: ComputerUseSetupModel

    private var preferenceBinding: Binding<AgentDesktopPreference> {
        Binding(get: { model.preference }, set: { model.preference = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Computer Use")
                    .font(TenXTypography.accent(size: 19))
                Spacer()
                Text(contractLabel)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(contractColor)
            }
            .padding(.top, 26)
            .padding(.bottom, 8)

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex))
                .frame(height: 2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Let this session verify work in dedicated app windows without taking over your desktop.")
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 30) {
                    Text("Agent Desktop")
                        .font(TenXTypography.body(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Agent Desktop", selection: preferenceBinding) {
                        Text("Automatic").tag(AgentDesktopPreference.automatic)
                        Text("AeroSpace").tag(AgentDesktopPreference.aeroSpace)
                        Text("Hammerspoon").tag(AgentDesktopPreference.hammerspoon)
                        Text("Background Only").tag(AgentDesktopPreference.backgroundOnly)
                    }
                    .labelsHidden()
                    .frame(width: 300, alignment: .trailing)
                    .accessibilityLabel("Agent Desktop")
                    .help("Choose the isolation helper for new sessions")
                }

                statusRow("OMP", value: "\(model.ompVersion) · \(contractDescription)")
                statusRow("Screen Recording", value: permissionLabel(model.readiness.capabilities.capture))
                statusRow("Accessibility", value: permissionLabel(model.readiness.capabilities.accessibility))
                statusRow("Background input", value: backgroundInputLabel)
                statusRow("Helper", value: helperLabel)

                if let harmlessTest = model.harmlessTest {
                    statusRow("Setup test", value: testOutcomeLabel(harmlessTest.outcome))
                    statusRow("Test capture", value: harmlessTest.captureSucceeded ? "Passed" : "Failed")
                    statusRow("Test accessibility", value: permissionLabel(harmlessTest.capabilities.accessibility))
                    statusRow("Test background input", value: testInputLabel(harmlessTest.backgroundInputSucceeded))
                    statusRow("Test helper", value: harmlessTest.helperAvailable ? "Passed" : "Failed")
                    statusRow("Test window placement", value: testPlacementLabel(harmlessTest.windowPlacementSucceeded))
                }

                if model.readiness.ompContract == .legacyBestEffort {
                    Text("Background control may still interrupt your current app")
                        .font(TenXTypography.body(size: 11, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button("Run setup test") { Task { await model.perform(.runHarmlessTest) } }
                        .buttonStyle(GhostActionStyle())
                        .accessibilityLabel("Run computer use setup test")
                        .help("Runs a check against a temporary 10x probe window")
                    Button("Screen Recording") { Task { await model.perform(.openScreenRecordingSettings) } }
                        .buttonStyle(GhostActionStyle())
                        .help("Open Screen Recording settings")
                    Button("Accessibility") { Task { await model.perform(.openAccessibilitySettings) } }
                        .buttonStyle(GhostActionStyle())
                        .help("Open Accessibility settings")
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("AeroSpace instructions") { Task { await model.perform(.showAeroSpaceInstructions) } }
                        .buttonStyle(GhostActionStyle())
                    Button("Hammerspoon instructions") { Task { await model.perform(.showHammerspoonInstructions) } }
                        .buttonStyle(GhostActionStyle())
                }
                if let instructions = model.instructions {
                    Text(instructions)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Helper setup instructions")
                }

                Text("10x enables this per session. New sessions always start off.")
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 15)
        }
        .task {
            if model.shouldAutomaticallyCheckReadiness {
                await model.runReadinessCheck()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 30) {
            Text(label)
                .font(TenXTypography.body(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .trailing)
                .accessibilityLabel("\(label): \(value)")
        }
    }

    private var contractLabel: String {
        switch model.readiness.ompContract {
        case .complete: "READY"
        case .legacyBestEffort: "BEST EFFORT"
        case .unavailable: "UNAVAILABLE"
        }
    }

    private var contractDescription: String {
        switch model.readiness.ompContract {
        case .complete: "Require handoff"
        case .legacyBestEffort: "Best effort"
        case .unavailable: "Unavailable"
        }
    }

    private var contractColor: Color {
        switch model.readiness.ompContract {
        case .complete: TenXPalette.color(TenXPalette.cyanHex)
        case .legacyBestEffort: TenXPalette.color(TenXPalette.yellowHex)
        case .unavailable: TenXPalette.color(TenXPalette.signalRedHex)
        }
    }

    private var backgroundInputLabel: String {
        guard let result = model.harmlessTest?.backgroundInputSucceeded else {
            return permissionLabel(model.readiness.capabilities.input)
        }
        return result ? "Verified" : "Not verified"
    }

    private var helperLabel: String {
        let probe = model.readiness.preferredProvider
        let version = probe.integrationVersion ?? "No version"
        switch probe.availability {
        case .healthy: return "Healthy · \(version)"
        case .missing: return "Not installed"
        case .incompatible: return "Incompatible"
        case .failed: return "Unavailable"
        }
    }

    private func permissionLabel(_ permission: ComputerPermissionState) -> String {
        switch permission {
        case .granted: "Granted"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        case .unknown: "Not checked"
        }
    }

    private func testOutcomeLabel(_ outcome: ComputerUseTestOutcome) -> String {
        switch outcome {
        case .passed: "Passed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private func testInputLabel(_ value: Bool?) -> String {
        guard let value else { return "Not checked" }
        return value ? "Passed" : "Failed"
    }

    private func testPlacementLabel(_ value: Bool?) -> String {
        guard let value else { return "Not applicable" }
        return value ? "Passed" : "Failed"
    }
}
