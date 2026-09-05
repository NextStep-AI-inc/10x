import SwiftUI

struct SettingsView: View {
    let model: SettingsViewModel
    let registry: IDERegistry
    let store: IDEPreferenceStore
    let focusTarget: SettingsFocusTarget?
    let onFocusConsumed: () -> Void
    let onBack: () -> Void
    let providerModel: ProviderManagementViewModel?
    let accountCoordinator: ProviderAccountCoordinator?
    let composerPreferences: ComposerInteractionPreferences

    @State private var showingProviders = false
    @State private var selectedOwner = SettingsOwner.omp
    @State private var selectedOMPCategory = SettingsCategory.general
    @State private var selectedTenXCategory = TenXSettingsCategory.general
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedControl: SettingsFocusTarget?

    init(
        model: SettingsViewModel,
        registry: IDERegistry = .init(),
        store: IDEPreferenceStore? = nil,
        focusTarget: SettingsFocusTarget? = nil,
        onFocusConsumed: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {},
        providerModel: ProviderManagementViewModel? = nil,
        accountCoordinator: ProviderAccountCoordinator? = nil,
        composerPreferences: ComposerInteractionPreferences = .shared
    ) {
        self.model = model
        self.registry = registry
        self.store = store ?? IDEPreferenceStore(registry: registry)
        self.focusTarget = focusTarget
        self.onFocusConsumed = onFocusConsumed
        self.onBack = onBack
        self.providerModel = providerModel
        self.accountCoordinator = accountCoordinator
        self.composerPreferences = composerPreferences
    }

    var body: some View {
        if showingProviders, let providerModel {
            ProvidersView(
                model: providerModel,
                accountCoordinator: accountCoordinator,
                onBack: { showingProviders = false })
        } else {
            settingsBody
        }
    }

    private var settingsBody: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                search
                categoryNavigation
                content(proxy: proxy)
            }
        }
        .frame(maxWidth: 960)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity)
        .task {
            if model.settingCount == 0 { await model.load() }
        }
        .onChange(of: availableOMPCategories) { _, categories in
            guard !categories.isEmpty, !categories.contains(selectedOMPCategory) else { return }
            selectedOMPCategory = categories[0]
        }
        .onChange(of: focusTarget, initial: true) { _, target in
            if model.prepareForFocus(target) {
                selectedOwner = .tenX
                selectedTenXCategory = .general
                isSearchFocused = false
            }
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
                Button(action: onBack) {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .offset(x: 1, y: 0.5)
                        Text("Back")
                    }
                }
                .buttonStyle(GhostActionStyle(
                    color: TenXPalette.color(TenXPalette.nearBlackHex),
                    horizontalPadding: 0))
                .accessibilityLabel("Back")
                .padding(.bottom, 8)
                Text("Settings")
                    .font(TenXTypography.title(size: 34))
            }
            Spacer()
            if providerModel != nil {
                Button("Providers") {
                    providerModel?.selectedSection = .connections
                    showingProviders = true
                }
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel("Open Providers")
            }
        }
        .padding(.top, 62)
        .padding(.bottom, 22)
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            TextField("Search all settings", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .font(TenXTypography.body(size: 14))
                .focused($isSearchFocused)
                .accessibilityLabel("Search all settings")
        }
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex))
                .frame(height: 2)
        }
    }

    private var categoryNavigation: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                ownerLabel(.omp)
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(availableOMPCategories) { category in
                            categoryButton(
                                category.title,
                                isSelected: selectedOwner == .omp && selectedOMPCategory == category
                            ) {
                                model.query = ""
                                selectedOwner = .omp
                                selectedOMPCategory = category
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                ownerLabel(.tenX)
                HStack(spacing: 14) {
                    ForEach(TenXSettingsCategory.allCases) { category in
                        categoryButton(
                            category.title,
                            isSelected: selectedOwner == .tenX && selectedTenXCategory == category
                        ) {
                            model.query = ""
                            selectedOwner = .tenX
                            selectedTenXCategory = category
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.top, 13)
        .padding(.bottom, 8)
    }

    private func ownerLabel(_ owner: SettingsOwner) -> some View {
        Text(owner.rawValue)
            .font(TenXTypography.mono(size: 9))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
    }

    private func categoryButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(TenXTypography.body(size: 11, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(TenXPalette.color(
                isSelected ? TenXPalette.cyanHex : TenXPalette.nearBlackHex))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        if hasQuery {
            searchResults(proxy: proxy)
        } else {
            switch selectedOwner {
            case .omp: ompContent
            case .tenX: nativeDocument(categories: [selectedTenXCategory], proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private var ompContent: some View {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ompMetadata
                    if let section = selectedOMPSection { ompSectionView(section) }
                }
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var ompMetadata: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.configPath.isEmpty ? "OMP configuration" : model.configPath)
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
            Spacer()
            Text("\(model.settingCount) settings")
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
        }
        .padding(.top, 18)
    }

    private func searchResults(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.sections.isEmpty {
                    searchOwnerHeader(.omp)
                    ompMetadata
                    ForEach(model.sections) { section in ompSectionView(section) }
                }
                if !matchingTenXCategories.isEmpty {
                    searchOwnerHeader(.tenX)
                    nativeSections(categories: matchingTenXCategories, proxy: proxy)
                }
                if model.sections.isEmpty && matchingTenXCategories.isEmpty {
                    Text("No settings match this search")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .padding(.vertical, 30)
                }
            }
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func searchOwnerHeader(_ owner: SettingsOwner) -> some View {
        Text(owner.rawValue)
            .font(TenXTypography.accent(size: 22))
            .padding(.top, 24)
            .padding(.bottom, 2)
    }

    private func ompSectionView(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(section.category.title, count: section.definitions.count)
            Rectangle().fill(sectionColor(section.category)).frame(height: 2)
            ForEach(section.definitions) { definition in
                SettingRowView(definition: definition, model: model)
                Divider()
            }
        }
    }

    private func nativeDocument(
        categories: [TenXSettingsCategory],
        proxy: ScrollViewProxy
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                nativeSections(categories: categories, proxy: proxy)
            }
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func nativeSections(
        categories: [TenXSettingsCategory],
        proxy: ScrollViewProxy
    ) -> some View {
        ForEach(categories) { category in
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(category.title, count: category == .general ? 1 : 4)
                Rectangle()
                    .fill(TenXPalette.color(TenXPalette.cyanHex))
                    .frame(height: 2)
                switch category {
                case .general:
                    PreferredIDESettingRowView(
                        registry: registry,
                        store: store,
                        focusedControl: $focusedControl)
                        .id(SettingsFocusTarget.preferredIDE)
                        .onAppear { focusPreferredIDEIfNeeded(proxy: proxy) }
                        .onChange(of: focusTarget) { _, _ in
                            focusPreferredIDEIfNeeded(proxy: proxy)
                        }
                case .composer:
                    ComposerInteractionSettingRows(preferences: composerPreferences)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(TenXTypography.accent(size: 19))
            Spacer()
            Text("\(count)")
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
        }
        .padding(.top, 26)
        .padding(.bottom, 8)
    }

    private var availableOMPCategories: [SettingsCategory] {
        model.catalog.sections(query: "").map(\.category)
    }

    private var selectedOMPSection: SettingsSection? {
        model.catalog.sections(query: "").first { $0.category == selectedOMPCategory }
    }

    private var matchingTenXCategories: [TenXSettingsCategory] {
        TenXSettingsCategory.allCases.filter {
            $0.matches(query: model.query, preferredIDEName: selectedApplicationName)
        }
    }

    private var hasQuery: Bool {
        !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedApplicationName: String? {
        switch store.state {
        case .none: nil
        case .available(let application): application.displayName
        case .unavailable(let displayName): displayName
        }
    }

    private func focusPreferredIDEIfNeeded(proxy: ScrollViewProxy) {
        guard focusTarget == .preferredIDE else { return }
        isSearchFocused = false
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(SettingsFocusTarget.preferredIDE, anchor: .center)
            focusedControl = .preferredIDE
            await Task.yield()
            onFocusConsumed()
        }
    }

    private func sectionColor(_ category: SettingsCategory) -> Color {
        switch category {
        case .safety: TenXPalette.color(TenXPalette.signalRedHex)
        case .advanced: TenXPalette.color(TenXPalette.yellowHex)
        default: TenXPalette.color(TenXPalette.cyanHex)
        }
    }
}
