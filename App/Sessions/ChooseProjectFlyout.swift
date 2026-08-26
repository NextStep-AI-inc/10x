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

/// Stepped silhouette: wide folder panel over a narrower choose-project rect.
struct TwoRectShelfShape: Shape {
    var topWidth: CGFloat
    var topHeight: CGFloat
    var bottomWidth: CGFloat
    var bottomHeight: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(topWidth, topHeight),
                AnimatablePair(bottomWidth, bottomHeight))
        }
        set {
            topWidth = newValue.first.first
            topHeight = newValue.first.second
            bottomWidth = newValue.second.first
            bottomHeight = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topW = min(topWidth, rect.width)
        let bottomW = min(bottomWidth, topW)
        let topH = topHeight
        let bottomH = bottomHeight

        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: topW, y: 0))
        path.addLine(to: CGPoint(x: topW, y: topH))
        path.addLine(to: CGPoint(x: bottomW, y: topH))
        path.addLine(to: CGPoint(x: bottomW, y: topH + bottomH))
        path.addLine(to: CGPoint(x: 0, y: topH + bottomH))
        path.closeSubpath()
        return path
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

    @State private var measuredTriggerWidth: CGFloat = 0

    private var widths: (top: CGFloat, bottom: CGFloat) {
        // ~intrinsic width of "📁 Choose project" until the real measure lands.
        let trigger = measuredTriggerWidth > 0 ? measuredTriggerWidth : 148
        return ChooseProjectFlyoutMetrics.panelWidths(triggerWidth: trigger)
    }

    private var topHeight: CGFloat {
        ChooseProjectFlyoutMetrics.topHeight(projectCount: projectURLs.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listPiece
                .frame(width: widths.top, height: topHeight, alignment: .topLeading)

            triggerPiece
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: ChooseProjectFlyoutMetrics.triggerHeight)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ShelfTriggerWidthKey.self,
                            value: geometry.size.width)
                    }
                }
        }
        .onPreferenceChange(ShelfTriggerWidthKey.self) { measuredTriggerWidth = $0 }
        .frame(
            width: widths.top,
            height: topHeight + ChooseProjectFlyoutMetrics.triggerHeight,
            alignment: .topLeading)
        .background {
            TwoRectShelfShape(
                topWidth: widths.top,
                topHeight: topHeight,
                bottomWidth: widths.bottom,
                bottomHeight: ChooseProjectFlyoutMetrics.triggerHeight)
            .fill(Color.white)
        }
        .overlay {
            TwoRectShelfShape(
                topWidth: widths.top,
                topHeight: topHeight,
                bottomWidth: widths.bottom,
                bottomHeight: ChooseProjectFlyoutMetrics.triggerHeight)
            .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
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
                height: ChooseProjectFlyoutMetrics.listHeight(projectCount: projectURLs.count))
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
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(projectURL?.lastPathComponent ?? "Choose project", systemImage: "folder")
                .lineLimit(1)
        }
        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.cyanHex)))
        .opacity(isPresented ? 0 : 1)
        .accessibilityHidden(isPresented)
        .accessibilityLabel("Choose project")
        .accessibilityValue(projectURL?.lastPathComponent ?? "None")
        .accessibilityHint("Shows project menu")
    }
}
