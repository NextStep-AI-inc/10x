import SwiftUI

struct SettingsView: View {
    let model: SettingsViewModel
    let registry: IDERegistry
    let store: IDEPreferenceStore
    let focusTarget: SettingsFocusTarget?
    let onFocusConsumed: () -> Void

    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedControl: SettingsFocusTarget?

    init(
        model: SettingsViewModel,
        registry: IDERegistry = .init(),
        store: IDEPreferenceStore? = nil,
        focusTarget: SettingsFocusTarget? = nil,
        onFocusConsumed: @escaping () -> Void = {}
    ) {
        self.model = model
        self.registry = registry
        self.store = store ?? IDEPreferenceStore(registry: registry)
        self.focusTarget = focusTarget
        self.onFocusConsumed = onFocusConsumed
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                searchAndAnchors(proxy: proxy)
                content(proxy: proxy)
            }
        }
        .frame(maxWidth: 960)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity)
        .task {
            if model.settingCount == 0 { await model.load() }
        }
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Settings")
                    .font(TenXTypography.title(size: 34))
                Text(model.configPath.isEmpty ? "OMP configuration" : model.configPath)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
            }
            Spacer()
            Text("\(model.settingCount) OMP settings")
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
        }
        .padding(.top, 62)
        .padding(.bottom, 22)
    }

    private func searchAndAnchors(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                TextField("Search all settings", text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .font(TenXTypography.body(size: 14))
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search all OMP settings")
            }
            .padding(.bottom, 9)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TenXPalette.color(TenXPalette.cyanHex))
                    .frame(height: 2)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 17) {
                    ForEach(SettingsCategory.allCases) { category in
                        Button(category.title) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                proxy.scrollTo(category, anchor: .top)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        if model.isLoading && model.settingCount == 0 {
            ProgressView("Loading OMP settings")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.loadError, model.settingCount == 0 {
            VStack(spacing: 14) {
                Text(error)
                    .font(TenXTypography.body(size: 12))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(GhostActionStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            settingsDocument(proxy: proxy)
        }
    }

    private func settingsDocument(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if documentSections.isEmpty {
                    Text("No settings match this search")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .padding(.vertical, 30)
                }
                ForEach(documentSections) { section in
                    sectionView(section, proxy: proxy)
                        .id(section.category)
                }
            }
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionView(_ section: SettingsSection, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(section.category.title)
                    .font(TenXTypography.accent(size: 19))
                Spacer()
                Text("\(section.definitions.count)")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            }
            .padding(.top, 26)
            .padding(.bottom, 8)

            Rectangle()
                .fill(sectionColor(section.category))
                .frame(height: 2)

            if section.category == .general && showsPreferredIDERow {
                PreferredIDESettingRowView(
                    registry: registry,
                    store: store,
                    focusedControl: $focusedControl)
                .id(SettingsFocusTarget.preferredIDE)
                .onAppear { focusPreferredIDEIfNeeded(proxy: proxy) }
                .onChange(of: focusTarget) { _, _ in
                    focusPreferredIDEIfNeeded(proxy: proxy)
                }

                if !section.definitions.isEmpty {
                    Divider()
                }
            }

            ForEach(section.definitions) { definition in
                SettingRowView(definition: definition, model: model)
                Divider()
            }
        }
    }

    private var documentSections: [SettingsSection] {
        let sections = model.sections
        guard showsPreferredIDERow, !sections.contains(where: { $0.category == .general }) else {
            return sections
        }
        return [SettingsSection(category: .general, definitions: [])] + sections
    }

    private var showsPreferredIDERow: Bool {
        PreferredIDESettingRowView.matches(
            query: model.query,
            applicationName: selectedApplicationName)
    }

    private var selectedApplicationName: String? {
        switch store.state {
        case .none:
            nil
        case .available(let application):
            application.displayName
        case .unavailable(let displayName):
            displayName
        }
    }

    private func focusPreferredIDEIfNeeded(proxy: ScrollViewProxy) {
        guard focusTarget == .preferredIDE else { return }
        proxy.scrollTo(SettingsFocusTarget.preferredIDE, anchor: .center)
        focusedControl = .preferredIDE
        onFocusConsumed()
    }

    private func sectionColor(_ category: SettingsCategory) -> Color {
        switch category {
        case .safety: TenXPalette.color(TenXPalette.signalRedHex)
        case .advanced: TenXPalette.color(TenXPalette.yellowHex)
        default: TenXPalette.color(TenXPalette.cyanHex)
        }
    }
}
