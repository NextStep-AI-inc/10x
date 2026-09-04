import OmpKit
import SwiftUI

struct FloatingRailView: View {
    let model: AppModel
    let expansion: RailExpansionModel
    @Binding var isBrandMenuPresented: Bool

    @FocusState private var focusedItem: RailFocus?
    @State private var expandedProjectIDs: Set<String> = []
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollNavigation = RailScrollNavigation.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [ProjectSessionGroup] {
        ProjectSessionGrouper.groups(model.sessions, knownProjectURLs: model.knownProjectURLs)
    }

    private var items: [RailPresentationItem] {
        RailPresentation.items(
            groups: groups,
            selectedSessionPath: selectedSessionPath,
            expandedProjectIDs: expansion.isExpanded ? expandedProjectIDs : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandMenuAnchor

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: RailMapLayout.minimumVerticalSpacing)
                    if !items.isEmpty {
                        sessionMap
                            .frame(height: RailMapLayout.height(
                                itemCount: items.count,
                                availableHeight: proxy.size.height))
                    }
                    Spacer(minLength: RailMapLayout.minimumVerticalSpacing)
                }
            }
            .frame(maxHeight: .infinity)

            Button(action: model.openArchivedSessions) {
                HStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .frame(width: 34)
                    if expansion.isExpanded {
                        Text("Archived")
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focusedItem, equals: .archived)
            .padding(.leading, 18)
            .frame(height: 44)
            .help("Archived sessions")
            .accessibilityLabel("Archived sessions")

        }
        .frame(width: expansion.contentLeadingInset, alignment: .leading)
        .contentShape(Rectangle())
        .onChange(of: focusedItem) { _, value in
            expansion.focusChanged(value != nil)
        }
        .onHover { isInside in
            if isInside {
                expansion.pointerEntered()
            } else if !isBrandMenuPresented {
                expansion.pointerExited()
            }
        }
        .onChange(of: isBrandMenuPresented) { _, presented in
            if presented {
                expansion.pointerEntered()
            } else {
                expansion.pointerExited()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Application navigation")
    }

    private var brandMenuAnchor: some View {
        Button {
            expansion.pointerEntered()
            isBrandMenuPresented.toggle()
        } label: {
            BrandWordmark(width: 34)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedItem, equals: .brandMenu)
        .frame(height: 44)
        .padding(.leading, 15)
        .padding(.top, 10)
        .help("Open actions")
        .accessibilityLabel(isBrandMenuPresented ? "Close actions" : "Open actions")
        .accessibilityAddTraits(isBrandMenuPresented ? .isSelected : [])
    }

    private var sessionMap: some View {
        VStack(spacing: 0) {
            if scrollNavigation.canScrollUp {
                scrollChevron(.up)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        itemButton(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: RailScrollNavigation.self) { geometry in
                RailScrollNavigation(
                    offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height)
            } action: { _, newValue in
                scrollNavigation = newValue
            }

            if scrollNavigation.canScrollDown {
                scrollChevron(.down)
            }
        }
    }

    private var selectedSessionPath: String? {
        if case .session(let path) = model.route { return path }
        return nil
    }

    @ViewBuilder
    private func itemButton(_ item: RailPresentationItem) -> some View {
        switch item.content {
        case .project(let group):
            Button {
                expansion.pointerEntered()
                if group.projectURL != ProjectSessionGroup.unknownProjectURL {
                    model.chooseProject(group.projectURL)
                }
            } label: {
                HStack(spacing: 12) {
                    RailTreeMarker(
                        label: item.markerLabel,
                        position: item.treePosition,
                        isSelected: false)
                        .frame(width: 34, height: 28)
                    if expansion.isExpanded {
                        Text(group.displayName)
                            .font(TenXTypography.body(size: 12, weight: .semibold))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RailProjectRowStyle())
            .focusEffectDisabled()
            .focused($focusedItem, equals: .project(group.id))
            .padding(.leading, 18)
            .frame(height: 32)
            .help("Start a new session in \(group.displayName)")
            .accessibilityLabel(group.displayName)
            .accessibilityHint(RailAccessibility.projectHint(group.displayName))
            .contextMenu {
                Button("Archive Project Sessions", systemImage: "archivebox") {
                    Task { await model.archiveProject(group) }
                }
                Button("Delete Project Sessions...", systemImage: "trash", role: .destructive) {
                    model.requestDeleteProject(group)
                }
            }

        case .session(let metadata):
            Button {
                expansion.pointerEntered()
                model.openSession(metadata)
            } label: {
                HStack(spacing: 12) {
                    RailTreeMarker(
                        label: item.markerLabel,
                        position: item.treePosition,
                        isSelected: item.isSelected)
                        .frame(width: 34, height: 28)
                    if expansion.isExpanded {
                        Text(metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session")
                            .font(TenXTypography.body(size: 12))
                            .foregroundStyle(item.isSelected
                                ? TenXPalette.color(TenXPalette.cyanHex)
                                : TenXPalette.color(TenXPalette.mutedTextHex))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focusedItem, equals: .session(metadata.path))
            .padding(.leading, 18)
            .frame(height: 32)
            .help(metadata.title ?? "Untitled session")
            .accessibilityLabel(RailAccessibility.sessionLabel(
                title: metadata.title ?? "Untitled session",
                project: groupName(for: metadata),
                state: metadata.status.rawValue.capitalized))
            .contextMenu {
                Button("Rename Session...", systemImage: "pencil") {
                    model.requestRenameSession(metadata)
                }
                Button("Archive Session", systemImage: "archivebox") {
                    Task { await model.archiveSession(metadata) }
                }
                Button("Delete Session...", systemImage: "trash", role: .destructive) {
                    model.requestDeleteSession(metadata)
                }
            }
            .accessibilityAction(named: Text("Rename Session")) {
                model.requestRenameSession(metadata)
            }

        case .disclosure(let disclosure):
            if expansion.isExpanded {
                Button {
                    toggleDisclosure(disclosure)
                } label: {
                    HStack(spacing: 12) {
                        RailTreeMarker(
                            label: "...",
                            position: .terminalChild,
                            isSelected: false)
                            .frame(width: 34, height: 28)
                        Text(disclosure.isExpanded
                            ? "Show recent 5"
                            : "Show \(disclosure.hiddenCount) more")
                            .font(TenXTypography.body(size: 11))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($focusedItem, equals: .disclosure(disclosure.projectID))
                .padding(.leading, 18)
                .frame(height: 32)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(RailAccessibility.disclosureLabel(
                    hiddenCount: disclosure.hiddenCount,
                    isExpanded: disclosure.isExpanded))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    toggleDisclosure(disclosure)
                }
            } else {
                RailTreeMarker(
                    label: "...",
                    position: .terminalChild,
                    isSelected: false)
                    .frame(width: 34, height: 28)
                    .padding(.leading, 18)
                    .frame(height: 32)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(RailAccessibility.hiddenSessionsLabel(
                        disclosure.hiddenCount))
            }
        }
    }

    private func toggleDisclosure(_ disclosure: RailProjectDisclosure) {
        if disclosure.isExpanded {
            expandedProjectIDs.remove(disclosure.projectID)
        } else {
            expandedProjectIDs.insert(disclosure.projectID)
        }
    }

    private func scrollChevron(_ direction: RailScrollDirection) -> some View {
        Button {
            let action = {
                scrollPosition.scrollTo(y: scrollNavigation.target(for: direction))
            }
            if reduceMotion {
                action()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    action()
                }
            }
        } label: {
            Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(TenXPalette.color(TenXPalette.canvasHex).opacity(0.9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedItem, equals: direction == .up ? .scrollUp : .scrollDown)
        .accessibilityLabel(RailAccessibility.scrollLabel(direction))
    }

    private func groupName(for metadata: SessionMetadata) -> String {
        groups.first(where: { group in
            group.sessions.contains(where: { $0.path == metadata.path })
        })?.displayName ?? "Unknown Project"
    }
}

private enum RailFocus: Hashable {
    case brandMenu
    case archived
    case scrollUp
    case scrollDown
    case project(String)
    case session(String)
    case disclosure(String)
}

/// Subtle hover cue for the project row so it reads as clickable, mirroring
/// `BrandMenuRowStyle`'s hover/pressed background treatment.
private struct RailProjectRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RailProjectRowBody(configuration: configuration)
    }
}

private struct RailProjectRowBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(
                isHovering || configuration.isPressed
                    ? TenXPalette.color(TenXPalette.hoverNeutralHex)
                    : .clear)
            .onHover { isHovering = $0 }
    }
}

private struct RailTreeMarker: View {
    let label: String
    let position: RailPresentationItem.TreePosition
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if position != .root {
                Canvas { context, size in
                    var path = Path()
                    let spineX: CGFloat = 4
                    let midY = size.height / 2

                    path.move(to: CGPoint(x: spineX, y: 0))
                    path.addLine(to: CGPoint(
                        x: spineX,
                        y: position == .terminalChild ? midY : size.height))
                    path.move(to: CGPoint(x: spineX, y: midY))
                    path.addLine(to: CGPoint(x: 10, y: midY))

                    context.stroke(
                        path,
                        with: .color(markerColor.opacity(isSelected ? 1 : 0.5)),
                        lineWidth: 1)
                }
                .frame(width: 11)
            }

            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(
                    width: position == .root ? 34 : 18,
                    alignment: position == .root ? .leading : .center)
                .offset(x: position == .root ? 0 : 12)
        }
        .accessibilityHidden(true)
    }

    private var markerColor: Color {
        if isSelected { return TenXPalette.color(TenXPalette.cyanHex) }
        if position == .root { return TenXPalette.color(TenXPalette.nearBlackHex) }
        return TenXPalette.color(TenXPalette.mutedTextHex)
    }
}
