import SwiftUI

enum ChooseProjectFlyoutMetrics {
    static let folderPanelWidth: CGFloat = 220
    static let rowHeight: CGFloat = 36
    static let addRowHeight: CGFloat = 32
    static let separatorHeight: CGFloat = 1
    static let maxListHeight: CGFloat = 180
    static let triggerHeight: CGFloat = 28
    static let maxPanelWidth: CGFloat = 280

    static func listHeight(projectCount: Int) -> CGFloat {
        let rows = CGFloat(max(projectCount, 1))
        return min(rows * rowHeight, maxListHeight)
    }

    static func topHeight(projectCount: Int) -> CGFloat {
        addRowHeight + separatorHeight + listHeight(projectCount: projectCount)
    }

    /// Folder panel is at least `folderPanelWidth` and never narrower than the trigger.
    static func panelWidths(triggerWidth: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let bottom = min(max(44, triggerWidth), maxPanelWidth)
        let top = min(max(folderPanelWidth, bottom), maxPanelWidth)
        return (top, bottom)
    }
}

private struct ShelfTriggerWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChooseProjectShelf: View {
    let projectURLs: [URL]
    let selectedProjectURL: URL?
    let triggerTitle: String
    let onChoose: (URL) -> Void
    let onAddExistingFolder: () -> Void
    let onToggle: () -> Void
    var placement: FlyoutPlacement? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var measuredTriggerWidth: CGFloat = 0

    private var widths: (top: CGFloat, bottom: CGFloat) {
        if let placement {
            return (
                placement.panelFrame.width,
                min(max(1, measuredTriggerWidth), placement.panelFrame.width))
        }
        // ~intrinsic width of "📁 Choose project" until the real measure lands.
        let trigger = measuredTriggerWidth > 0 ? measuredTriggerWidth : 148
        return ChooseProjectFlyoutMetrics.panelWidths(triggerWidth: trigger)
    }

    private var topHeight: CGFloat {
        placement?.panelFrame.height
            ?? ChooseProjectFlyoutMetrics.topHeight(projectCount: projectURLs.count)
    }

    var body: some View {
        ConnectedFlyoutShelf(
            panelSize: CGSize(width: widths.top, height: topHeight),
            triggerSize: CGSize(
                width: widths.bottom,
                height: ChooseProjectFlyoutMetrics.triggerHeight),
            triggerOffsetX: placement?.triggerOffsetX ?? 0,
            direction: placement?.direction ?? .above,
            fill: TenXPalette.surfaceElevated,
            onDismiss: onDismiss ?? onToggle,
            panelContent: {
                listPiece
                    .frame(width: widths.top, height: topHeight, alignment: .topLeading)
            },
            triggerContent: {
                triggerPiece
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ShelfTriggerWidthKey.self,
                                value: geometry.size.width)
                        }
                    }
            })
        .onPreferenceChange(ShelfTriggerWidthKey.self) { measuredTriggerWidth = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose project")
    }

    private var listPiece: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onAddExistingFolder) {
                Label("Add folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ChooseProjectFlyoutMetrics.addRowHeight)

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: ChooseProjectFlyoutMetrics.separatorHeight)
                .padding(.horizontal, 8)

            ScrollView {
                VStack(spacing: 0) {
                    if projectURLs.isEmpty {
                        Text("No projects yet")
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .frame(height: ChooseProjectFlyoutMetrics.rowHeight)
                    } else {
                        ForEach(projectURLs, id: \.path) { url in
                            projectRow(url)
                                .frame(height: ChooseProjectFlyoutMetrics.rowHeight)
                        }
                    }
                }
            }
            .frame(
                width: widths.top,
                height: min(
                    ChooseProjectFlyoutMetrics.listHeight(projectCount: projectURLs.count),
                    max(0, topHeight
                        - ChooseProjectFlyoutMetrics.addRowHeight
                        - ChooseProjectFlyoutMetrics.separatorHeight)))
        }
    }

    private var triggerPiece: some View {
        Button(action: onToggle) {
            Label(triggerTitle, systemImage: "folder")
                .lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))
        .accessibilityLabel("Choose project")
        .accessibilityValue(triggerTitle)
        .accessibilityHint("Menu open")
    }

    private func projectRow(_ url: URL) -> some View {
        let isSelected = selectedProjectURL?.standardizedFileURL.path
            == url.standardizedFileURL.path
        return Button {
            onChoose(url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TenXPalette.color(
                        isSelected ? TenXPalette.cyanHex : TenXPalette.mutedTextHex))
                    .frame(width: 14)
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
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FlyoutRowBackground(isSelected: isSelected))
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(isSelected ? "Selected" : url.path)
        .help(url.path)
    }
}

struct FlyoutRowBackground: View {
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
    var onRestoreFocus: () -> Void = {}

    @State private var anchor: FlyoutWindowAnchor?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var triggerTitle: String {
        projectURL?.lastPathComponent ?? "Choose project"
    }

    private var desiredPanelSize: CGSize {
        let triggerWidth = anchor?.triggerFrame.width ?? 148
        return CGSize(
            width: ChooseProjectFlyoutMetrics.panelWidths(triggerWidth: triggerWidth).top,
            height: ChooseProjectFlyoutMetrics.topHeight(projectCount: projectURLs.count))
    }

    private var placement: FlyoutPlacement? {
        anchor.map {
            FlyoutPlacement.resolve(
                triggerFrame: $0.triggerFrame,
                desiredPanelSize: desiredPanelSize,
                usableBounds: $0.usableBounds,
                preferredDirection: .above)
        }
    }

    var body: some View {
        trigger
            .background {
                FlyoutWindowAnchorReader { nextAnchor in
                    if anchor != nextAnchor { anchor = nextAnchor }
                }
            }
            .overlay(alignment: .topLeading) {
                if isPresented {
                    ChooseProjectShelf(
                        projectURLs: projectURLs,
                        selectedProjectURL: projectURL,
                        triggerTitle: triggerTitle,
                        onChoose: { url in
                            closeAndRestoreFocus()
                            onChoose(url)
                        },
                        onAddExistingFolder: {
                            closeAndRestoreFocus()
                            onAddExistingFolder()
                        },
                        onToggle: closeAndRestoreFocus,
                        placement: resolvedPlacement,
                        onDismiss: { isPresented = false })
                    .offset(x: panelOffsetX, y: panelOffsetY)
                    .transition(transition)
                    .zIndex(3)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isPresented)
            .onExitCommand {
                guard isPresented else { return }
                closeAndRestoreFocus()
            }
    }

    private var trigger: some View {
        Button {
            if isPresented {
                closeAndRestoreFocus()
            } else {
                isPresented = true
            }
        } label: {
            Label(triggerTitle, systemImage: "folder").lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))
        .opacity(isPresented ? 0 : 1)
        .accessibilityHidden(isPresented)
        .accessibilityLabel("Choose project")
        .accessibilityValue(projectURL?.lastPathComponent ?? "None")
        .accessibilityHint("Shows project menu")
    }

    private var resolvedPlacement: FlyoutPlacement {
        placement ?? FlyoutPlacement(
            direction: .above,
            panelFrame: CGRect(origin: .zero, size: desiredPanelSize),
            triggerOffsetX: 0,
            isHeightConstrained: false)
    }

    private var panelOffsetX: CGFloat {
        guard let anchor, let placement else { return 0 }
        return placement.panelFrame.minX - anchor.triggerFrame.minX
    }

    private var panelOffsetY: CGFloat {
        resolvedPlacement.direction == .above ? -resolvedPlacement.panelFrame.height : 0
    }

    private var transition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let offset = resolvedPlacement.direction == .above ? 8.0 : -8.0
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offset)),
            removal: .opacity.combined(with: .offset(y: offset / 2)))
    }

    private func closeAndRestoreFocus() {
        isPresented = false
        onRestoreFocus()
    }
}
