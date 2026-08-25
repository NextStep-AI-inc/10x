import SwiftUI

struct SettingsView: View {
    let model: SettingsViewModel

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                searchAndAnchors(proxy: proxy)
                content
            }
        }
        .frame(maxWidth: 960)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity)
        .task {
            if model.settingCount == 0 { await model.load() }
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
            Text("\(model.settingCount) settings")
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
    private var content: some View {
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
            settingsDocument
        }
    }

    private var settingsDocument: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.sections.isEmpty {
                    Text("No settings match this search")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .padding(.vertical, 30)
                }
                ForEach(model.sections) { section in
                    sectionView(section)
                        .id(section.category)
                }
            }
            .padding(.bottom, 60)
        }
        .scrollIndicators(.hidden)
    }

    private func sectionView(_ section: SettingsSection) -> some View {
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

            ForEach(section.definitions) { definition in
                SettingRowView(definition: definition, model: model)
                Divider()
            }
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
