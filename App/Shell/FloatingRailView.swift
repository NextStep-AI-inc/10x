import SwiftUI

struct FloatingRailView: View {
    let model: AppModel
    let expansion: RailExpansionModel

    @FocusState private var focusedItem: RailFocus?

    private var groups: [ProjectSessionGroup] {
        ProjectSessionGrouper.groups(model.sessions)
    }

    private var items: [RailPresentationItem] {
        RailPresentation.items(groups: groups, selectedSessionPath: selectedSessionPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandWordmark(width: expansion.isExpanded ? 42 : 34)
                .frame(height: 44)
                .padding(.leading, 15)
                .padding(.top, 10)

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer(minLength: 18)

                    VStack(alignment: .leading, spacing: 22) {
                        actionStack

                        if !items.isEmpty {
                            sessionMap
                                .frame(height: sessionMapHeight(availableHeight: proxy.size.height))
                        }
                    }

                    Spacer(minLength: 18)
                }
            }

            profile
                .padding(.bottom, 18)
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
        .animation(.easeInOut(duration: 0.2), value: expansion.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Application navigation")
    }

    private var actionStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            railAction(
                title: "New session",
                systemImage: "plus",
                focus: .newSession,
                isSelected: model.route == .newSession
            ) {
                expansion.pointerEntered()
                model.route = .newSession
            }

            railAction(
                title: "Search",
                systemImage: "magnifyingglass",
                focus: .search
            ) {
                expansion.pointerEntered()
                model.isSearchPresented = true
            }

            railAction(
                title: "Settings",
                systemImage: "gearshape",
                focus: .settings,
                isSelected: model.route == .settings
            ) {
                expansion.pointerEntered()
                model.route = .settings
            }
        }
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

    private var profile: some View {
        HStack(spacing: 12) {
            Text("TP")
                .font(TenXTypography.body(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(TenXPalette.color(TenXPalette.nearBlackHex))
                .clipShape(Circle())
            if expansion.isExpanded {
                Text("Tanner Pham")
                    .font(TenXTypography.body(size: 12, weight: .medium))
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 17)
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

    private func railAction(
        title: String,
        systemImage: String,
        focus: RailFocus,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                if expansion.isExpanded {
                    Text(title)
                        .font(TenXTypography.body(size: 12, weight: .medium))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isSelected
                ? TenXPalette.color(TenXPalette.cyanHex)
                : TenXPalette.color(TenXPalette.nearBlackHex))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($focusedItem, equals: focus)
        .padding(.leading, 17)
        .frame(height: 36)
        .accessibilityLabel(title)
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
                    ProjectMarker()
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
                    SessionMarker(isSelected: item.isSelected)
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
            .accessibilityLabel(metadata.title ?? "Untitled session")
        }
    }
}

private enum RailFocus: Hashable {
    case newSession
    case search
    case settings
    case project(String)
    case session(String)
}

private struct ProjectMarker: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let inset: CGFloat = 8
            let length: CGFloat = 6

            path.move(to: CGPoint(x: inset, y: inset + length))
            path.addLine(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: inset + length, y: inset))
            path.move(to: CGPoint(x: size.width - inset - length, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - length))

            context.stroke(
                path,
                with: .color(TenXPalette.color(TenXPalette.nearBlackHex)),
                lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct SessionMarker: View {
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .fill(isSelected
                ? TenXPalette.color(TenXPalette.cyanHex)
                : TenXPalette.color(TenXPalette.nearBlackHex))
            .frame(width: isSelected ? 18 : 12, height: isSelected ? 2 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
