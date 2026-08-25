import OmpKit
import SwiftUI

struct FloatingRailView: View {
    let model: AppModel
    let expansion: RailExpansionModel

    @FocusState private var focusedItem: RailFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [ProjectSessionGroup] {
        ProjectSessionGrouper.groups(model.sessions)
    }

    private var items: [RailPresentationItem] {
        RailPresentation.items(groups: groups, selectedSessionPath: selectedSessionPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expansion.pointerEntered()
                model.openSettings()
            } label: {
                BrandWordmark(width: expansion.isExpanded ? 42 : 34)
                    .frame(width: 44, height: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .focused($focusedItem, equals: .settings)
                .frame(height: 44)
                .padding(.leading, 15)
                .padding(.top, 10)
                .help("Open Settings")
                .accessibilityLabel("Open Settings")
                .keyboardShortcut(",", modifiers: .command)

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 18)

                    if !items.isEmpty {
                        sessionMap
                            .frame(height: sessionMapHeight(availableHeight: proxy.size.height))
                    }

                    Spacer(minLength: 18)
                }
            }

            if !model.providerUsages.isEmpty {
                ProviderUsageLedgerView(providers: model.providerUsages)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                    .frame(height: usageLedgerHeight)
                    .opacity(expansion.isExpanded ? 1 : 0)
                    .allowsHitTesting(expansion.isExpanded)
                    .accessibilityHidden(!expansion.isExpanded)
            }
        }
        .frame(width: expansion.isExpanded ? 220 : 64, alignment: .leading)
        .contentShape(Rectangle())
        .onChange(of: focusedItem) { _, value in
            expansion.focusChanged(value != nil)
        }
        .onHover { isInside in
            if isInside {
                expansion.pointerEntered()
            } else {
                expansion.pointerExited()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expansion.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Application navigation")
    }

    private var sessionMap: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    itemButton(item)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var usageLedgerHeight: CGFloat {
        let limitCount = model.providerUsages.reduce(0) { $0 + $1.limits.count }
        return min(210, CGFloat(48 + model.providerUsages.count * 28 + limitCount * 21))
    }

    private var selectedSessionPath: String? {
        if case .session(let path) = model.route { return path }
        return nil
    }

    private func sessionMapHeight(availableHeight: CGFloat) -> CGFloat {
        let desiredHeight = CGFloat(items.count) * 26
        let maximumHeight = max(104, availableHeight * 0.58)
        return min(desiredHeight, maximumHeight)
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
                        .frame(width: 30, height: 22)
                    if expansion.isExpanded {
                        Text(group.displayName)
                            .font(TenXTypography.body(size: 11, weight: .semibold))
                            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($focusedItem, equals: .project(group.id))
            .padding(.leading, 17)
            .frame(height: 26)
            .help(group.projectURL.path)
            .accessibilityLabel(group.displayName)

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
                        .frame(width: 30, height: 22)
                    if expansion.isExpanded {
                        Text(metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session")
                            .font(TenXTypography.body(size: 11))
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
            .padding(.leading, 17)
            .frame(height: 26)
            .help(metadata.title ?? "Untitled session")
            .accessibilityLabel(RailAccessibility.sessionLabel(
                title: metadata.title ?? "Untitled session",
                project: groupName(for: metadata),
                state: metadata.status.rawValue.capitalized))
        }
    }

    private func groupName(for metadata: SessionMetadata) -> String {
        groups.first(where: { group in
            group.sessions.contains(where: { $0.path == metadata.path })
        })?.displayName ?? "Unknown Project"
    }
}

private enum RailFocus: Hashable {
    case settings
    case project(String)
    case session(String)
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
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(width: position == .root ? 30 : 17, alignment: .center)
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
