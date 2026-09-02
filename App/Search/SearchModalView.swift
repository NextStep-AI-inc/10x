import SwiftUI
import OmpKit

struct SearchModalView: View {
    let sessions: [SessionMetadata]
    let service: any SessionSearching
    let onOpen: (SearchResult) -> Void
    let onClose: () -> Void

    @State private var model: SearchModalModel
    @FocusState private var isSearchFocused: Bool

    init(
        sessions: [SessionMetadata],
        service: any SessionSearching,
        onOpen: @escaping (SearchResult) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.sessions = sessions
        self.service = service
        self.onOpen = onOpen
        self.onClose = onClose
        _model = State(initialValue: SearchModalModel(sessions: sessions, service: service))
    }

    var body: some View {
        ZStack {
            TenXPalette.color(TenXPalette.canvasHex).opacity(0.94)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                searchHeader
                Divider()
                resultBody
            }
            .frame(width: 780, height: 520)
            .background(TenXPalette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(TenXPalette.color(TenXPalette.nearBlackHex), lineWidth: 1)
            }
            .onTapGesture { }
        }
        .task {
            await Task.yield()
            isSearchFocused = true
        }
        .onDisappear { model.cancelSearch() }
        .onChange(of: sessions) { _, sessions in model.updateSessions(sessions) }
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search sessions")
    }

    private var searchHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                TextField("Search sessions, messages, and tools", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(TenXTypography.body(size: 18))
                    .focused($isSearchFocused)
                    .onSubmit(openSelection)
                Button("Close", action: onClose)
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.signalRedHex)))
                    .keyboardShortcut(.escape, modifiers: [])
            }

            HStack(spacing: 16) {
                Text("FILTER")
                    .font(TenXTypography.mono(size: 9, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                filterButton(title: "All", kind: nil)
                ForEach(SearchResultKind.allCases, id: \.self) { kind in
                    filterButton(title: kind.label + "s", kind: kind)
                }
                Spacer()
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !model.query.isEmpty {
                    Text("\(model.visibleResults.count) results")
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var resultBody: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.query.isEmpty {
                        emptyPrompt("Type to search local session history")
                    } else if !model.isSearching && model.visibleResults.isEmpty {
                        emptyPrompt("No matching local activity")
                    } else {
                        ForEach(model.visibleResults) { result in
                            resultButton(result)
                        }
                    }
                }
            }
            .frame(width: 330)

            Divider()

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var preview: some View {
        Group {
            if let result = selectedResult {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(result.kind.label.uppercased())
                            .font(TenXTypography.mono(size: 9, weight: .semibold))
                            .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                        Spacer()
                        Text("↩ Open")
                            .font(TenXTypography.mono(size: 10))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    Text(result.title)
                        .font(TenXTypography.title(size: 27))
                    Text(result.projectPath)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                    Text(result.excerpt)
                        .font(TenXTypography.body(size: 13))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                        .textSelection(.enabled)
                    Spacer()
                    Button("Open session", action: openSelection)
                        .buttonStyle(GhostActionStyle())
                }
                .padding(24)
            } else {
                Color.clear
            }
        }
    }

    private var selectedResult: SearchResult? {
        model.visibleResults.first { $0.id == model.selectedResultID }
    }

    private func resultButton(_ result: SearchResult) -> some View {
        Button {
            model.select(result)
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(result.id == model.selectedResultID
                        ? TenXPalette.color(TenXPalette.cyanHex)
                        : .clear)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(result.title)
                            .font(TenXTypography.body(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(result.kind.label)
                            .font(TenXTypography.mono(size: 9))
                            .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    }
                    Text(result.excerpt)
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                }
                .padding(.vertical, 12)
                .padding(.trailing, 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(result.id == model.selectedResultID
            ? TenXPalette.color(TenXPalette.hoverNeutralHex)
            : .clear)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(result) })
        .accessibilityLabel("\(result.kind.label), \(result.title)")
    }

    private func filterButton(title: String, kind: SearchResultKind?) -> some View {
        let isSelected: Bool
        if let kind {
            isSelected = model.filters == Set([kind])
        } else {
            isSelected = model.filters == Set(SearchResultKind.allCases)
        }
        return Button(title) {
            if let kind {
                model.toggle(kind)
            } else {
                model.filters = Set(SearchResultKind.allCases)
            }
        }
        .buttonStyle(.plain)
        .font(TenXTypography.body(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected
            ? TenXPalette.color(TenXPalette.cyanHex)
            : TenXPalette.color(TenXPalette.nearBlackHex))
    }

    private func emptyPrompt(_ text: String) -> some View {
        Text(text)
            .font(TenXTypography.body(size: 12))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
    }

    private func openSelection() {
        guard let selectedResult else { return }
        onOpen(selectedResult)
    }
}
