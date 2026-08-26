import SwiftUI

struct BrandActionsMenuView: View {
    let model: AppModel
    @Binding var isPresented: Bool
    private let revealsImmediately: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed: Bool

    private let items: [BrandActionItem] = [
        BrandActionItem(
            id: "search",
            title: "Search",
            systemImage: "magnifyingglass",
            isSelected: { $0.isSearchPresented },
            perform: { $0.openSearch() }),
        BrandActionItem(
            id: "new-session",
            title: "New session",
            systemImage: "plus",
            isSelected: { $0.route == .newSession },
            perform: { $0.openNewSession() }),
        BrandActionItem(
            id: "new-project",
            title: "New project",
            systemImage: "folder.badge.plus",
            isSelected: { _ in false },
            perform: { $0.chooseNewProject() }),
        BrandActionItem(
            id: "settings",
            title: "Settings",
            systemImage: "gearshape",
            isSelected: { $0.route == .settings },
            perform: { $0.openSettings() }),
    ]

    init(
        model: AppModel,
        isPresented: Binding<Bool>,
        revealsImmediately: Bool = false
    ) {
        self.model = model
        _isPresented = isPresented
        self.revealsImmediately = revealsImmediately
        _isRevealed = State(initialValue: revealsImmediately)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                menuRow(item, index: index)
            }
        }
        .padding(6)
        .frame(width: 188, alignment: .leading)
        .background(.white)
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
        }
        // ponytail: drawer unfold; ceiling ~4 rows — switch to List if the menu grows.
        .mask(alignment: .top) {
            Rectangle()
                .frame(height: isRevealed ? 1000 : 0)
                .animation(
                    (reduceMotion || revealsImmediately)
                        ? nil
                        : .spring(response: 0.3, dampingFraction: 0.88),
                    value: isRevealed)
        }
        .onAppear { isRevealed = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("10x actions")
    }

    private func menuRow(_ item: BrandActionItem, index: Int) -> some View {
        let isSelected = item.isSelected(model)
        let delay = reduceMotion || revealsImmediately ? 0 : Double(index) * 0.045

        return Button {
            item.perform(model)
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                Text(item.title)
                    .font(TenXTypography.body(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected
                ? TenXPalette.color(TenXPalette.cyanHex)
                : TenXPalette.color(TenXPalette.nearBlackHex))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(BrandMenuRowStyle())
        .offset(x: isRevealed ? 0 : -14)
        .animation(
            (reduceMotion || revealsImmediately)
                ? nil
                : .spring(response: 0.32, dampingFraction: 0.86).delay(delay),
            value: isRevealed)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct BrandActionsKeyboardShortcuts: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Button(action: model.openSearch) { EmptyView() }
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityHidden(true)
            Button(action: model.openNewSession) { EmptyView() }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityHidden(true)
            Button { model.openSettings() } label: { EmptyView() }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityHidden(true)
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BrandActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isSelected: (AppModel) -> Bool
    let perform: (AppModel) -> Void
}

private struct BrandMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BrandMenuRowBody(configuration: configuration)
    }
}

private struct BrandMenuRowBody: View {
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
