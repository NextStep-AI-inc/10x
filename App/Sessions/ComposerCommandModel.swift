import Foundation
import Observation
import OmpKit

@MainActor
protocol ComposerCommandSession: AnyObject {
    var runtimeState: SessionRuntimeState { get }
    var commandCatalogState: ComposerCommandCatalogState { get }
    var commandUpdates: AsyncStream<ComposerCommandCatalogState> { get }
    func sendSlashCommand(_ text: String) async
}

enum CommandBrowserRoute: Equatable, Sendable {
    case root
    case subcommands(CommandBrowserRowID)
    case arguments(CommandBrowserRowID)
    case native(AppCommand)
}

enum CommandBrowserMove: Sendable {
    case previous
    case next
    case first
    case last
    case pagePrevious
    case pageNext
}

enum CommandBrowserCycle: Sendable {
    case forward
    case backward
}

enum CommandBrowserEffect: Equatable, Sendable {
    case none
    case keepDraft
    case dismiss
    case replaceDraft(String)
    case executed
}

@MainActor
@Observable
final class ComposerCommandModel {
    private(set) var isPresented = false
    private(set) var selectedSource: CommandBrowserSource = .all
    private(set) var selectedRowID: CommandBrowserRowID?
    private(set) var route: CommandBrowserRoute = .root
    private(set) var catalogState: ComposerCommandCatalogState = .loading
    private(set) var inlineMessage: String?
    private(set) var selectedSubcommandUsage: String?

    @ObservationIgnored private let warmCatalog: any ComposerCatalogLoading
    @ObservationIgnored private let controls: ComposerControlsModel
    @ObservationIgnored private let onStartNewSession: @MainActor (String, [ComposerAttachment]) -> Void
    @ObservationIgnored private weak var activeSession: (any ComposerCommandSession)?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var warmStreamTask: Task<Void, Never>?
    @ObservationIgnored private var streamGeneration = 0
    @ObservationIgnored private var warmCatalogState: ComposerCommandCatalogState = .loading
    @ObservationIgnored private var commands: [AvailableSlashCommand] = []
    @ObservationIgnored private var parsedDraft: ParsedSlashDraft?
    @ObservationIgnored private var selectedSubcommandName: String?
    @ObservationIgnored private var invalidatedChildRowID: CommandBrowserRowID?
    @ObservationIgnored private var draft = ""
    @ObservationIgnored private var mode: CommandBrowserMode = .newSession

    init(
        catalog: any ComposerCatalogLoading,
        controls: ComposerControlsModel,
        onStartNewSession: @escaping @MainActor (String, [ComposerAttachment]) -> Void
    ) {
        warmCatalog = catalog
        self.controls = controls
        self.onStartNewSession = onStartNewSession
        observeWarmCatalog(catalog.commandUpdates)
    }

    deinit {
        streamTask?.cancel()
        warmStreamTask?.cancel()
    }

    var visibleRows: [CommandBrowserRow] {
        presentation.rows
    }

    var sources: [CommandBrowserSourceItem] {
        presentation.sources
    }

    var highlightedRow: CommandBrowserRow? {
        visibleRows.first { $0.id == selectedRowID }
    }

    private var presentation: CommandBrowserResult {
        CommandBrowserPresentation.present(
            commands: commands,
            query: parsedDraft?.query ?? "",
            selectedSource: selectedSource,
            mode: resolvedMode)
    }

    private var resolvedMode: CommandBrowserMode {
        guard catalogState != .unavailable else { return .unavailable }
        guard let activeSession else { return .newSession }
        return activeSession.runtimeState == .streaming ? .activeStreaming : .activeIdle
    }

    @discardableResult
    func updateDraft(_ text: String) -> Bool {
        let priorSelection = selectedRowID
        draft = text
        clearInvalidatedChildRecovery()
        guard let parsed = CommandBrowserPresentation.parseDraft(text) else {
            parsedDraft = nil
            clearSelectedSubcommand()
            isPresented = false
            route = .root
            inlineMessage = nil
            selectedRowID = nil
            return false
        }
        parsedDraft = parsed
        isPresented = true
        if shouldKeepArgumentRoute(for: parsed) {
            inlineMessage = nil
            return true
        }
        if route != .root {
            route = .root
            clearSelectedSubcommand()
        }
        inlineMessage = nil
        refreshSelection(previous: priorSelection)
        return true
    }

    func moveSelection(_ move: CommandBrowserMove) {
        guard route == .root else { return }
        let rows = visibleRows
        guard !rows.isEmpty else {
            selectedRowID = nil
            return
        }
        let current = selectedRowID.flatMap { id in rows.firstIndex { $0.id == id } }
        let last = rows.index(before: rows.endIndex)
        let page = max(1, min(8, rows.count))
        let index: Int
        switch move {
        case .first:
            index = rows.startIndex
        case .last:
            index = last
        case .previous:
            index = current.map { $0 == rows.startIndex ? last : $0 - 1 } ?? last
        case .next:
            index = current.map { $0 == last ? rows.startIndex : $0 + 1 } ?? rows.startIndex
        case .pagePrevious:
            index = max(rows.startIndex, (current ?? rows.startIndex) - page)
        case .pageNext:
            index = min(last, (current ?? rows.startIndex) + page)
        }
        let nextSelection = rows[index].id
        if nextSelection != selectedRowID {
            clearInvalidatedChildRecovery()
        }
        selectedRowID = nextSelection
    }

    func cycleSource(_ cycle: CommandBrowserCycle) {
        let visibleSources = sources.map(\.id)
        guard let current = visibleSources.firstIndex(of: selectedSource), !visibleSources.isEmpty else { return }
        let index: Int
        switch cycle {
        case .forward:
            index = current == visibleSources.index(before: visibleSources.endIndex) ? visibleSources.startIndex : current + 1
        case .backward:
            index = current == visibleSources.startIndex ? visibleSources.index(before: visibleSources.endIndex) : current - 1
        }
        selectSource(visibleSources[index])
    }

    func selectVisibleSource(at oneBasedIndex: Int) {
        let visibleSources = sources.map(\.id)
        guard visibleSources.indices.contains(oneBasedIndex - 1) else { return }
        selectSource(visibleSources[oneBasedIndex - 1])
    }

    func selectSource(_ source: CommandBrowserSource) {
        guard route == .root, sources.contains(where: { $0.id == source }) else { return }
        let priorSelection = selectedRowID
        selectedSource = source
        clearSelectedSubcommand()
        selectedRowID = presentation.initialSelection
        if selectedRowID != priorSelection {
            clearInvalidatedChildRecovery()
        }
    }

    func highlight(_ rowID: CommandBrowserRowID?) {
        guard route == .root else { return }
        let nextSelection = CommandBrowserPresentation.retainedSelection(rowID, in: visibleRows)
        if let nextSelection, nextSelection != selectedRowID {
            clearInvalidatedChildRecovery()
        }
        selectedRowID = nextSelection
    }

    func complete() -> CommandBrowserEffect {
        guard let row = highlightedRow else { return .none }
        switch row.kind {
        case .app(let command):
            route = .native(command)
            return .keepDraft
        case .omp:
            let requiresStage = needsArgumentStage(row) || !row.subcommands.isEmpty
            let canonical = canonicalSlashText(for: row, trailingSpace: requiresStage)
            if !requiresStage {
                dismissPresentation()
                return .replaceDraft(canonical)
            }
            route = row.subcommands.isEmpty ? .arguments(row.id) : .subcommands(row.id)
            clearSelectedSubcommand()
            draft = canonical
            parsedDraft = CommandBrowserPresentation.parseDraft(canonical)
            return .replaceDraft(canonical)
        }
    }

    func selectSubcommand(named name: String) -> CommandBrowserEffect {
        guard case .subcommands(let rowID) = route else { return .none }
        guard let row = row(for: rowID) else { return unavailableChildEffect() }
        guard let subcommand = row.subcommands.first(where: { $0.name == name }) else { return .none }
        let canonicalName = subcommand.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonicalName.isEmpty else { return .none }

        selectedSubcommandName = subcommand.name
        selectedSubcommandUsage = subcommand.usage
        route = .arguments(rowID)
        let canonical = "/\(row.canonicalName) \(canonicalName) "
        draft = canonical
        parsedDraft = CommandBrowserPresentation.parseDraft(canonical)
        return .replaceDraft(canonical)
    }

    func activate(attachments: [ComposerAttachment] = []) async -> CommandBrowserEffect {
        switch route {
        case .native:
            return .none
        case .subcommands(let rowID):
            guard row(for: rowID) != nil else { return unavailableChildEffect() }
            return .none
        case .arguments(let rowID):
            guard let row = row(for: rowID) else { return unavailableChildEffect() }
            return await execute(row: row, attachments: attachments)
        case .root:
            guard invalidatedChildRowID == nil else { return .none }
            guard let row = highlightedRow else {
                return await executeTypedDraft(attachments: attachments)
            }
            switch row.kind {
            case .app(let command):
                route = .native(command)
                return .keepDraft
            case .omp:
                if !row.subcommands.isEmpty {
                    let canonical = canonicalSlashText(for: row, trailingSpace: true)
                    route = .subcommands(row.id)
                    clearSelectedSubcommand()
                    draft = canonical
                    parsedDraft = CommandBrowserPresentation.parseDraft(canonical)
                    return .replaceDraft(canonical)
                }
                if needsArgumentStage(row) {
                    let canonical = canonicalSlashText(for: row, trailingSpace: true)
                    route = .arguments(row.id)
                    draft = canonical
                    parsedDraft = CommandBrowserPresentation.parseDraft(canonical)
                    return .replaceDraft(canonical)
                }
                return await execute(row: row, attachments: attachments)
            }
        }
    }

    func applyModel(_ model: ComposerModelInfo) async -> CommandBrowserEffect {
        guard route == .native(.model) else { return .none }
        let remainder = parsedDraft?.arguments ?? ""
        let outcome = await controls.selectModel(
            model,
            mode: activeSession == nil ? .newSession : .activeSession)
        return completeNativeMutation(outcome, remainder: remainder)
    }

    func applyEffort(_ effort: String) async -> CommandBrowserEffect {
        guard route == .native(.effort) else { return .none }
        let remainder = parsedDraft?.arguments ?? ""
        let outcome = await controls.selectThinking(
            effort,
            mode: activeSession == nil ? .newSession : .activeSession)
        return completeNativeMutation(outcome, remainder: remainder)
    }

    func applyFast(_ isEnabled: Bool) async -> CommandBrowserEffect {
        guard route == .native(.fast) else { return .none }
        let remainder = parsedDraft?.arguments ?? ""
        let outcome = await controls.setFastMode(
            isEnabled,
            mode: activeSession == nil ? .newSession : .activeSession)
        return completeNativeMutation(outcome, remainder: remainder)
    }

    func back() -> CommandBrowserEffect {
        guard route != .root else { return dismiss() }
        route = .root
        clearSelectedSubcommand()
        inlineMessage = nil
        refreshSelection(previous: selectedRowID)
        return .keepDraft
    }

    func dismiss() -> CommandBrowserEffect {
        dismissPresentation()
        return .dismiss
    }

    func attachActiveSession(_ session: any ComposerCommandSession) {
        activeSession = session
        attach(stream: session.commandUpdates, initial: session.commandCatalogState)
    }

    func detachActiveSession() {
        activeSession = nil
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        applyCatalogState(warmCatalogState)
    }

    func stopObservingCatalog() {
        detachActiveSession()
        warmStreamTask?.cancel()
        warmStreamTask = nil
    }

    #if DEBUG
    var testingCatalogIdentity: ObjectIdentifier {
        ObjectIdentifier(warmCatalog)
    }

    var isAttachedToActiveSession: Bool {
        activeSession != nil
    }

    var testingIsObservingCatalog: Bool {
        warmStreamTask != nil || streamTask != nil
    }
    #endif

    private func observeWarmCatalog(_ stream: AsyncStream<ComposerCommandCatalogState>) {
        warmStreamTask = Task { [weak self] in
            for await state in stream {
                guard !Task.isCancelled, let self else { return }
                self.warmCatalogState = state
                guard self.activeSession == nil else { continue }
                self.applyCatalogState(state)
            }
        }
    }

    private func attach(stream: AsyncStream<ComposerCommandCatalogState>, initial: ComposerCommandCatalogState) {
        streamGeneration += 1
        let generation = streamGeneration
        streamTask?.cancel()
        applyCatalogState(initial)
        streamTask = Task { [weak self] in
            for await state in stream {
                guard !Task.isCancelled else { return }
                guard let self, self.streamGeneration == generation else { return }
                self.applyCatalogState(state)
            }
        }
    }

    private func applyCatalogState(_ state: ComposerCommandCatalogState) {
        let previousRows = visibleRows
        let previousSelection = selectedRowID
        catalogState = state
        switch state {
        case .loading:
            commands = []
        case .available(let available):
            commands = available
        case .unavailable:
            commands = []
        }
        mode = resolvedMode
        switch route {
        case .subcommands(let rowID):
            if row(for: rowID) == nil {
                markUnavailableChild(for: rowID)
            }
        case .arguments(let rowID):
            guard let row = row(for: rowID) else {
                markUnavailableChild(for: rowID)
                break
            }
            if let selectedSubcommandName {
                guard let selected = row.subcommands.first(where: { $0.name == selectedSubcommandName }) else {
                    markUnavailableChild(for: rowID)
                    break
                }
                selectedSubcommandUsage = selected.usage
            }
        case .root, .native:
            break
        }
        refreshSelection(previous: previousSelection, previousRows: previousRows)
    }

    private func refreshSelection(
        previous: CommandBrowserRowID?,
        previousRows: [CommandBrowserRow]? = nil
    ) {
        let result = presentation
        if let retained = CommandBrowserPresentation.retainedSelection(previous, in: result.rows) {
            selectedRowID = retained
            return
        }
        if let previousRows, let previous,
           let priorIndex = previousRows.firstIndex(where: { $0.id == previous }), !result.rows.isEmpty
        {
            selectedRowID = result.rows[min(priorIndex, result.rows.index(before: result.rows.endIndex))].id
            return
        }
        selectedRowID = result.initialSelection
    }

    private func row(for id: CommandBrowserRowID) -> CommandBrowserRow? {
        CommandBrowserPresentation.rows(commands: commands, mode: resolvedMode).first { $0.id == id }
    }

    private func shouldKeepArgumentRoute(for parsed: ParsedSlashDraft) -> Bool {
        guard case .arguments(let rowID) = route,
              let row = row(for: rowID),
              matches(row: row, token: parsed.query)
        else { return false }
        guard let selectedSubcommandName else { return true }
        guard let subcommand = row.subcommands.first(where: { $0.name == selectedSubcommandName }),
              firstArgumentToken(in: parsed.arguments) == selectedSubcommandName
        else { return false }
        selectedSubcommandUsage = subcommand.usage
        return true
    }

    private func matches(row: CommandBrowserRow, token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([row.canonicalName] + row.aliases).contains(trimmed)
    }

    private func firstArgumentToken(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let boundary = trimmed.firstIndex(where: \.isWhitespace) ?? trimmed.endIndex
        return String(trimmed[..<boundary])
    }

    private func needsArgumentStage(_ row: CommandBrowserRow) -> Bool {
        guard case .omp = row.kind else { return false }
        return row.inputHint != nil || row.source == .skills || row.source == .prompts
    }

    private func canonicalSlashText(for row: CommandBrowserRow, trailingSpace: Bool = false) -> String {
        let unindented = draft.drop { $0 == " " || $0 == "\t" }
        guard unindented.first == "/" else {
            return "/\(row.canonicalName)" + (trailingSpace ? " " : "")
        }
        let afterSlash = unindented.dropFirst()
        let boundary = afterSlash.firstIndex(where: \.isWhitespace) ?? afterSlash.endIndex
        let suffix = String(afterSlash[boundary...])
        if trailingSpace, suffix.isEmpty {
            return "/\(row.canonicalName) "
        }
        return "/\(row.canonicalName)\(suffix)"
    }

    private func execute(row: CommandBrowserRow, attachments: [ComposerAttachment]) async -> CommandBrowserEffect {
        let text = canonicalSlashText(for: row)
        if let activeSession {
            await activeSession.sendSlashCommand(text)
            dismissPresentation()
            return .executed
        }
        guard row.source == .skills || row.source == .prompts else { return .none }
        onStartNewSession(text, attachments)
        dismissPresentation()
        return .executed
    }

    private func executeTypedDraft(attachments: [ComposerAttachment]) async -> CommandBrowserEffect {
        let text = canonicalTypedDraft()
        guard text.first == "/", catalogState != .unavailable else { return .none }
        if let activeSession {
            await activeSession.sendSlashCommand(text)
            dismissPresentation()
            return .executed
        }
        return .none
    }

    private func canonicalTypedDraft() -> String {
        String(draft.drop { $0 == " " || $0 == "\t" })
    }

    private func completeNativeMutation(
        _ outcome: ComposerControlsMutationOutcome,
        remainder: String
    ) -> CommandBrowserEffect {
        switch outcome {
        case .success:
            dismissPresentation()
            return .replaceDraft(remainder)
        case .failure(let message):
            inlineMessage = message
            return .none
        }
    }

    private func unavailableChildEffect() -> CommandBrowserEffect {
        markUnavailableChild(for: childRowID)
        refreshSelection(previous: selectedRowID)
        return .keepDraft
    }

    private var childRowID: CommandBrowserRowID? {
        switch route {
        case .subcommands(let rowID), .arguments(let rowID): rowID
        case .root, .native: nil
        }
    }

    private func markUnavailableChild(for rowID: CommandBrowserRowID?) {
        route = .root
        clearSelectedSubcommand()
        invalidatedChildRowID = rowID
        inlineMessage = "This command is no longer available."
    }

    private func clearInvalidatedChildRecovery() {
        guard invalidatedChildRowID != nil else { return }
        invalidatedChildRowID = nil
        inlineMessage = nil
    }

    private func clearSelectedSubcommand() {
        selectedSubcommandName = nil
        selectedSubcommandUsage = nil
    }

    private func dismissPresentation() {
        isPresented = false
        selectedSource = .all
        selectedRowID = nil
        route = .root
        inlineMessage = nil
        invalidatedChildRowID = nil
        parsedDraft = nil
        clearSelectedSubcommand()
        draft = ""
    }

}
