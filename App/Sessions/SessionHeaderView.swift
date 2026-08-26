import SwiftUI

struct SessionHeaderView: View {
    let controller: SessionController
    private let phaseOverride: ComputerUsePhase?
    private let safetyModeOverride: ComputerUseSafetyMode?
    private let isCompleteContractOverride: Bool?
    @State private var isBestEffortConfirmationPresented = false

    init(
        controller: SessionController,
        phaseOverride: ComputerUsePhase? = nil,
        safetyModeOverride: ComputerUseSafetyMode? = nil,
        isCompleteContractOverride: Bool? = nil
    ) {
        self.controller = controller
        self.phaseOverride = phaseOverride
        self.safetyModeOverride = safetyModeOverride
        self.isCompleteContractOverride = isCompleteContractOverride
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(controller.title)
                    .font(TenXTypography.body(size: 13, weight: .semibold))
                    .lineLimit(1)
                if showsComputerControls {
                    Spacer(minLength: 8)
                    computerControls
                }
            }

            if !controller.headerMetadata.presentationItems.isEmpty {
                HStack(spacing: 14) {
                    ForEach(controller.headerMetadata.presentationItems) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 9, weight: .medium))
                            Text(item.value)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.accessibilityLabel)
                        .accessibilityValue(item.value)
                    }
                }
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: 680)
        .frame(height: 54)
        .padding(.leading, 42)
        .padding(.trailing, 92)
        .confirmationDialog(
            "Enable best-effort computer use?",
            isPresented: $isBestEffortConfirmationPresented,
            titleVisibility: .visible)
        {
            Button("Enable Best Effort") {
                Task { await controller.computerUse.enable(safetyMode: .legacyBestEffort) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This OMP version cannot guarantee that computer control will stay in the background.")
        }
    }

    @ViewBuilder
    private var computerControls: some View {
        HStack(spacing: 4) {
            Text("Computer: \(phaseLabel)")
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            if isBestEffortBadgeVisible {
                Text("Best effort")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay {
                        Rectangle()
                            .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
                    }
            }
            if isEnabled {
                Button("Stop Computer") {
                    Task { await controller.computerUse.stopComputerUse() }
                }
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(TenXPalette.signalRedHex)))
                .accessibilityLabel("Stop computer control for this session")
            } else if phase == .off {
                Button(isCompleteContract ? "Enable Computer" : "Enable Best Effort") {
                    if isCompleteContract {
                        Task { await controller.computerUse.enable() }
                    } else {
                        isBestEffortConfirmationPresented = true
                    }
                }
                .buttonStyle(GhostActionStyle())
            }
        }
    }

    private var phase: ComputerUsePhase { phaseOverride ?? controller.computerUse.phase }
    private var safetyMode: ComputerUseSafetyMode {
        safetyModeOverride ?? controller.computerUse.safetyMode
    }
    private var isCompleteContract: Bool {
        isCompleteContractOverride ?? controller.computerUse.isCompleteContractAvailable
    }
    private var showsComputerControls: Bool {
        phaseOverride != nil || controller.computerUse.isSessionAttached
    }
    private var isEnabled: Bool {
        switch phase {
        case .preparing, .ready, .controlling, .needsHandoff, .stopping:
            true
        case .off, .unavailable:
            false
        }
    }
    private var isBestEffortBadgeVisible: Bool {
        guard safetyMode == .legacyBestEffort else { return false }
        return switch phase {
        case .ready, .controlling: true
        default: false
        }
    }
    private var phaseLabel: String {
        switch phase {
        case .off: "Off"
        case .preparing: "Preparing"
        case .ready: "Ready"
        case .controlling: "Controlling"
        case .needsHandoff: "Needs handoff"
        case .unavailable: "Unavailable"
        case .stopping: "Stopping"
        }
    }
}
