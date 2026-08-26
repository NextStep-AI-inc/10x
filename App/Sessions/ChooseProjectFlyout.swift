import SwiftUI

enum ChooseProjectFlyoutMetrics {
    static let width: CGFloat = 220
    static let maxHeight: CGFloat = 220
}

struct ChooseProjectFlyout: View {
    let projectURLs: [URL]
    let selectedProjectURL: URL?
    let onChoose: (URL) -> Void
    let onAddExistingFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if projectURLs.isEmpty {
                        Text("No projects yet")
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(projectURLs, id: \.path) { url in
                            projectRow(url)
                        }
                    }
                }
            }
            .frame(maxHeight: ChooseProjectFlyoutMetrics.maxHeight - 36)

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)

            Button(action: onAddExistingFolder) {
                Label("Add folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))
            .padding(2)
        }
        .frame(width: ChooseProjectFlyoutMetrics.width, alignment: .leading)
        .background(.white)
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose project")
    }

    private func projectRow(_ url: URL) -> some View {
        let isSelected = selectedProjectURL?.standardizedFileURL.path
            == url.standardizedFileURL.path
        return Button {
            onChoose(url)
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isSelected
                        ? TenXPalette.color(TenXPalette.cyanHex)
                        : .clear)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        .lineLimit(1)
                    Text(url.path)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FlyoutRowBackground(isSelected: isSelected))
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(isSelected ? "Selected" : url.path)
        .help(url.path)
    }
}

private struct FlyoutRowBackground: View {
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        TenXPalette.color(
            isSelected || isHovering
                ? TenXPalette.hoverNeutralHex
                : TenXPalette.canvasHex
        )
        .onHover { isHovering = $0 }
    }
}

struct ChooseProjectControl: View {
    let projectURL: URL?
    let projectURLs: [URL]
    let onChoose: (URL) -> Void
    let onAddExistingFolder: () -> Void

    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(projectURL?.lastPathComponent ?? "Choose project", systemImage: "folder")
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))
        .accessibilityLabel("Choose project")
        .accessibilityValue(projectURL?.lastPathComponent ?? "None")
        .accessibilityHint(isPresented ? "Menu open" : "Shows project menu")
        .background(alignment: .bottomLeading) {
            if isPresented {
                ChooseProjectFlyout(
                    projectURLs: projectURLs,
                    selectedProjectURL: projectURL,
                    onChoose: {
                        onChoose($0)
                        isPresented = false
                    },
                    onAddExistingFolder: {
                        isPresented = false
                        onAddExistingFolder()
                    })
                // Sit flush on the control: bottom of flyout meets top of button.
                .offset(y: -28)
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPresented)
        .zIndex(isPresented ? 1 : 0)
        .onExitCommand {
            isPresented = false
        }
    }
}
