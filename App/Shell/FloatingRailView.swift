import OmpKit
import SwiftUI

struct FloatingRailView: View {
    let model: AppModel
    let expansion: RailExpansionModel

    @FocusState private var hasKeyboardFocus: Bool

    private var groups: [ProjectSessionGroup] {
        ProjectSessionGrouper.groups(model.sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandWordmark(width: expansion.isExpanded ? 42 : 34)
                .frame(height: 44)
                .padding(.horizontal, 11)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                railAction(
                    title: "New session",
                    systemImage: "plus",
                    isSelected: model.route == .newSession
                ) {
                    model.route = .newSession
                }

                railAction(title: "Search", systemImage: "magnifyingglass") {
                    model.isSearchPresented = true
                }

                railAction(
                    title: "Settings",
                    systemImage: "gearshape",
                    isSelected: model.route == .settings
                ) {
                    model.route = .settings
                }
            }
            .padding(.top, 22)

            if expansion.isExpanded {
                projectTree
                    .transition(.opacity)
            } else {
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
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
                }
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
        .frame(width: expansion.isExpanded ? 200 : 64, alignment: .leading)
        .contentShape(Rectangle())
        .focusable()
        .focused($hasKeyboardFocus)
        .onChange(of: hasKeyboardFocus) { _, value in
            expansion.focusChanged(value)
        }
        .onHover { isInside in
            if isInside {
                expansion.pointerEntered()
            } else {
                expansion.pointerExited()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expansion.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Application navigation")
    }

    private var projectTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Button {
                            if group.projectURL != ProjectSessionGroup.unknownProjectURL {
                                model.chooseProject(group.projectURL)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.displayName)
                                    .font(TenXTypography.body(size: 12, weight: .semibold))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                                    .lineLimit(1)
                                if group.projectURL != ProjectSessionGroup.unknownProjectURL {
                                    Text(group.projectURL.deletingLastPathComponent().path)
                                        .font(TenXTypography.mono(size: 9))
                                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        ForEach(group.sessions) { session in
                            Button {
                                model.openSession(session)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Rectangle()
                                        .fill(session.path == selectedSessionPath
                                            ? TenXPalette.color(TenXPalette.cyanHex)
                                            : .clear)
                                        .frame(width: 2, height: 14)
                                    Text(session.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session")
                                        .font(TenXTypography.body(size: 11))
                                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(session.title ?? "Untitled session")
                        }
                    }
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.never)
    }

    private var selectedSessionPath: String? {
        if case .session(let path) = model.route { return path }
        return nil
    }

    private func railAction(
        title: String,
        systemImage: String,
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
                }
            }
            .foregroundStyle(isSelected
                ? TenXPalette.color(TenXPalette.cyanHex)
                : TenXPalette.color(TenXPalette.nearBlackHex))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 17)
        .frame(height: 36)
        .accessibilityLabel(title)
    }
}
