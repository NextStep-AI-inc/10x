import AppKit
import OmpKit
import SwiftUI

struct ComputerToolCardView: View {
    let presentation: ToolPresentation
    @State private var selectedImageID: String?
    @State private var isCodeExpanded = false
    @State private var isRawDetailsExpanded = false

    init(presentation: ToolPresentation) {
        self.presentation = presentation
        let parsed = ComputerToolPresentation(presentation)
        _selectedImageID = State(initialValue: parsed?.images.last?.id)
    }

    var body: some View {
        if let computer = ComputerToolPresentation(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Computer",
                subtitle: computer.target
            ) {
                summary(computer)
                imageEvidence(computer)
                output(computer)
                capabilityFailures(computer)
                codeDisclosure(computer)
                rawDetailsDisclosure(computer)
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }

    private func summary(_ computer: ComputerToolPresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ComputerSummaryRow(label: "State", value: presentation.phase.label)
            ComputerSummaryRow(label: "Target", value: computer.target ?? "Desktop")
            ComputerSummaryRow(label: "Mode", value: computer.mode.label)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func imageEvidence(_ computer: ComputerToolPresentation) -> some View {
        if let image = selectedImage(in: computer.images),
           let nativeImage = NSImage(data: image.data) {
            VStack(alignment: .leading, spacing: 7) {
                Text(computer.images.count == 1 ? "Screenshot" : "Latest screenshot")
                    .font(TenXTypography.body(size: 10, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))

                Image(nsImage: nativeImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .accessibilityLabel("Computer screenshot")

                if computer.images.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(computer.images.enumerated()), id: \.element.id) { index, item in
                                if let thumbnail = NSImage(data: item.data) {
                                    Button {
                                        selectedImageID = item.id
                                    } label: {
                                        Image(nsImage: thumbnail)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 92, height: 58)
                                            .overlay {
                                                Rectangle().stroke(
                                                    TenXPalette.color(item.id == image.id
                                                        ? TenXPalette.cyanHex
                                                        : TenXPalette.separatorHex),
                                                    lineWidth: item.id == image.id ? 2 : 1)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Show screenshot \(index + 1)")
                                    .accessibilityValue(item.id == image.id ? "Selected" : "")
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityLabel("Computer screenshot gallery")
                }
            }
        }
    }

    @ViewBuilder
    private func output(_ computer: ComputerToolPresentation) -> some View {
        let evidence = computer.outputEvidence
        if evidence.isEmpty, presentation.phase == .complete {
            Text("No output")
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }

        ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
            outputEvidence(item)
        }
    }

    @ViewBuilder
    private func outputEvidence(_ evidence: ComputerOutputEvidence) -> some View {
        switch evidence {
        case .output(let value):
            evidenceSection(title: "Output") {
                BoundedToolOutputView(
                    text: value,
                    lineLimit: 8,
                    font: TenXTypography.mono(size: 10),
                    color: TenXPalette.color(presentation.isError
                        ? TenXPalette.signalRedHex
                        : TenXPalette.nearBlackHex),
                    isDisclosureAlwaysAvailable: true)
            }
        case .returnValue(let value):
            evidenceSection(title: "Return value") {
                BoundedToolOutputView(
                    text: value,
                    lineLimit: 6,
                    font: TenXTypography.mono(size: 10),
                    isDisclosureAlwaysAvailable: true)
            }
        }
    }

    @ViewBuilder
    private func capabilityFailures(_ computer: ComputerToolPresentation) -> some View {
        let failures = capabilityFailureMessages(computer.capabilities)
        if !failures.isEmpty {
            evidenceSection(title: "Unavailable capabilities") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(failures, id: \.self) { failure in
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(TenXTypography.body(size: 11))
                            .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func codeDisclosure(_ computer: ComputerToolPresentation) -> some View {
        if !computer.code.isEmpty {
            DisclosureGroup("Computer code", isExpanded: $isCodeExpanded) {
                CodeBlockView(language: "javascript", code: computer.code)
                    .padding(.top, 6)
            }
            .font(TenXTypography.body(size: 11, weight: .medium))
            .tint(TenXPalette.color(TenXPalette.cyanHex))
        }
    }

    @ViewBuilder
    private func rawDetailsDisclosure(_ computer: ComputerToolPresentation) -> some View {
        if let details = computer.rawDetails {
            DisclosureGroup("Raw details", isExpanded: $isRawDetailsExpanded) {
                BoundedToolOutputView(
                    text: formatted(details),
                    lineLimit: 12,
                    font: TenXTypography.mono(size: 10),
                    isDisclosureAlwaysAvailable: true)
                    .padding(.top, 6)
            }
            .font(TenXTypography.body(size: 11, weight: .medium))
            .tint(TenXPalette.color(TenXPalette.cyanHex))
        }
    }

    private func evidenceSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(TenXTypography.body(size: 10, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            content()
        }
    }

    private func selectedImage(in images: [ComputerImage]) -> ComputerImage? {
        images.first { $0.id == selectedImageID } ?? images.last
    }

    private func capabilityFailureMessages(_ capabilities: ComputerCapabilities) -> [String] {
        guard capabilities.backend != "unknown" else { return [] }
        return [
            capabilityMessage("Screen capture", state: capabilities.capture),
            capabilityMessage("Background input", state: capabilities.input),
            capabilityMessage("Accessibility", state: capabilities.accessibility),
        ].compactMap { $0 }
    }

    private func capabilityMessage(
        _ name: String,
        state: ComputerPermissionState
    ) -> String? {
        switch state {
        case .granted:
            nil
        case .denied:
            "\(name) permission denied"
        case .unavailable:
            "\(name) unavailable"
        case .unknown:
            "\(name) status unavailable"
        }
    }

    private func formatted(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "Unavailable" }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct ComputerSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(TenXTypography.body(size: 10, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
