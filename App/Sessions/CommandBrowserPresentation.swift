import Foundation
import OmpKit

enum CommandBrowserSource: String, CaseIterable, Hashable, Sendable {
    case all = "All"
    case app = "App"
    case commands = "Commands"
    case skills = "Skills"
    case extensions = "Extensions"
    case prompts = "Prompts"
    case other = "Other"
}

enum CommandBrowserMode: Equatable, Sendable {
    case newSession
    case activeIdle
    case activeStreaming
    case unavailable
}

enum AppCommand: String, CaseIterable, Hashable, Sendable {
    case model
    case effort
    case fast
}

struct CommandBrowserRowID: Hashable, Sendable {
    let rawSource: String
    let canonicalName: String
}

struct CommandBrowserRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case app(AppCommand)
        case omp(AvailableSlashCommand)
    }

    let id: CommandBrowserRowID
    let canonicalName: String
    let aliases: [String]
    let summary: String
    let inputHint: String?
    let subcommands: [AvailableSlashSubcommand]
    let source: CommandBrowserSource
    let rawSource: String
    let kind: Kind
    let availabilityMessage: String?
    let executionNote: String?
}

struct ParsedSlashDraft: Equatable, Sendable {
    let query: String
    let arguments: String
}

struct CommandBrowserResult: Equatable, Sendable {
    let sources: [CommandBrowserSourceItem]
    let rows: [CommandBrowserRow]
    let heading: String?
    let initialSelection: CommandBrowserRowID?
}

struct CommandBrowserSourceItem: Identifiable, Equatable, Sendable {
    let id: CommandBrowserSource
    let count: Int
    let message: String?
}

enum CommandBrowserPresentation {
    private static let unavailableMessage =
        "Model, Effort, and Fast remain available. Retry after the session reconnects."
    private static let newSessionMessage = "Start a session to use OMP commands."

    static func parseDraft(_ draft: String) -> ParsedSlashDraft? {
        let leadingWhitespace = draft.prefix { $0 == " " || $0 == "\t" }
        let remainder = draft.dropFirst(leadingWhitespace.count)
        guard remainder.first == "/" else { return nil }

        let token = remainder.dropFirst()
        guard let separator = token.firstIndex(where: \.isWhitespace) else {
            return ParsedSlashDraft(query: String(token), arguments: "")
        }
        let query = String(token[..<separator])
        let argumentStart = token.index(after: separator)
        let arguments = String(token[argumentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedSlashDraft(query: query, arguments: arguments)
    }

    static func source(for source: AvailableSlashCommandSource) -> CommandBrowserSource {
        switch source {
        case .builtin:
            .commands
        case .skill:
            .skills
        case .extensionCommand:
            .extensions
        case .custom, .mcpPrompt, .file:
            .prompts
        case .other:
            .other
        }
    }

    static func rows(commands: [AvailableSlashCommand], mode: CommandBrowserMode) -> [CommandBrowserRow] {
        let appRows = AppCommand.allCases.map { appRow(for: $0, mode: mode) }
        guard mode != .unavailable else { return appRows }

        let visibleSources: Set<CommandBrowserSource>
        switch mode {
        case .newSession:
            visibleSources = [.skills, .prompts]
        case .activeIdle, .activeStreaming:
            visibleSources = [.commands, .skills, .extensions, .prompts, .other]
        case .unavailable:
            visibleSources = []
        }

        let appNames = Set(AppCommand.allCases.map { $0.rawValue.lowercased() })
        var seen = Set<CommandBrowserRowID>()
        let ompRows = commands.compactMap { command -> CommandBrowserRow? in
            let canonicalName = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let commandSource = source(for: command.source)
            let rawSource = command.source.rawValue
            let id = CommandBrowserRowID(rawSource: rawSource, canonicalName: canonicalName)
            guard !canonicalName.isEmpty,
                  !rawSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !appNames.contains(canonicalName.lowercased()),
                  visibleSources.contains(commandSource),
                  seen.insert(id).inserted
            else { return nil }

            return CommandBrowserRow(
                id: id,
                canonicalName: canonicalName,
                aliases: command.aliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                summary: command.description ?? "",
                inputHint: command.inputHint,
                subcommands: command.subcommands,
                source: commandSource,
                rawSource: rawSource,
                kind: .omp(command),
                availabilityMessage: nil,
                executionNote: mode == .activeStreaming ? "Runs after the current response" : nil)
        }

        return appRows + ompRows.sorted(by: stableRowOrder)
    }

    static func present(
        commands: [AvailableSlashCommand],
        query: String,
        selectedSource: CommandBrowserSource,
        mode: CommandBrowserMode
    ) -> CommandBrowserResult {
        let availableRows = rows(commands: commands, mode: mode)
        let sourceItems = sources(for: availableRows, mode: mode)
        let sourceRows = selectedSource == .all
            ? availableRows
            : availableRows.filter { $0.source == selectedSource }
        if mode == .newSession,
           selectedSource == .commands || selectedSource == .extensions {
            return CommandBrowserResult(
                sources: sourceItems,
                rows: [],
                heading: newSessionMessage,
                initialSelection: nil)
        }
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !needle.isEmpty else {
            return CommandBrowserResult(
                sources: sourceItems,
                rows: sourceRows,
                heading: mode == .unavailable ? "Session commands unavailable" : nil,
                initialSelection: sourceRows.first?.id)
        }

        let directMatches = sourceRows.compactMap { row -> (row: CommandBrowserRow, rank: Int)? in
            guard let rank = directRank(for: row, needle: needle) else { return nil }
            return (row, rank)
        }.sorted { lhs, rhs in
            lhs.rank == rhs.rank ? stableRowOrder(lhs.row, rhs.row) : lhs.rank < rhs.rank
        }
        if !directMatches.isEmpty {
            let matchedRows = directMatches.map(\.row)
            return CommandBrowserResult(
                sources: sourceItems,
                rows: matchedRows,
                heading: nil,
                initialSelection: matchedRows.first?.id)
        }

        let closeMatches = sourceRows.compactMap { row -> (row: CommandBrowserRow, distance: Int)? in
            guard let distance = closeDistance(for: row, needle: needle) else { return nil }
            return (row, distance)
        }.sorted { lhs, rhs in
            lhs.distance == rhs.distance ? stableRowOrder(lhs.row, rhs.row) : lhs.distance < rhs.distance
        }
        if !closeMatches.isEmpty {
            return CommandBrowserResult(
                sources: sourceItems,
                rows: closeMatches.map(\.row),
                heading: "Close results",
                initialSelection: nil)
        }

        if mode == .unavailable {
            return CommandBrowserResult(
                sources: sourceItems,
                rows: [],
                heading: "Session commands unavailable",
                initialSelection: nil)
        }

        return CommandBrowserResult(
            sources: sourceItems,
            rows: [],
            heading: "No commands match “/\(query)”.",
            initialSelection: nil)
    }

    static func retainedSelection(
        _ selectedID: CommandBrowserRowID?,
        in rows: [CommandBrowserRow]
    ) -> CommandBrowserRowID? {
        guard let selectedID, rows.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }

    private static func appRow(for command: AppCommand, mode: CommandBrowserMode) -> CommandBrowserRow {
        let summary: String
        switch command {
        case .model:
            summary = "Choose a model"
        case .effort:
            summary = "Choose reasoning effort"
        case .fast:
            summary = "Toggle fast mode"
        }
        return CommandBrowserRow(
            id: CommandBrowserRowID(rawSource: "app", canonicalName: command.rawValue),
            canonicalName: command.rawValue,
            aliases: [],
            summary: summary,
            inputHint: nil,
            subcommands: [],
            source: .app,
            rawSource: "app",
            kind: .app(command),
            availabilityMessage: nil,
            executionNote: mode == .activeStreaming ? "Applies to the next request" : nil)
    }

    private static func sources(
        for rows: [CommandBrowserRow],
        mode: CommandBrowserMode
    ) -> [CommandBrowserSourceItem] {
        let hasOther = rows.contains { $0.source == .other }
        return CommandBrowserSource.allCases.filter { $0 != .other || hasOther }.map { source in
            let count = source == .all ? rows.count : rows.filter { $0.source == source }.count
            return CommandBrowserSourceItem(
                id: source,
                count: count,
                message: sourceMessage(for: source, mode: mode))
        }
    }

    private static func sourceMessage(
        for source: CommandBrowserSource,
        mode: CommandBrowserMode
    ) -> String? {
        switch mode {
        case .newSession where source == .commands || source == .extensions:
            newSessionMessage
        case .unavailable where source != .all && source != .app:
            unavailableMessage
        default:
            nil
        }
    }

    private static func directRank(for row: CommandBrowserRow, needle: String) -> Int? {
        let names = [row.canonicalName] + row.aliases
        if names.contains(where: { normalized($0) == needle }) { return 0 }
        if names.contains(where: { normalized($0).hasPrefix(needle) }) { return 1 }
        if names.contains(where: { hasWordBoundaryMatch($0, needle: needle) }) { return 2 }
        if names.contains(where: { normalized($0).contains(needle) }) { return 3 }
        if row.subcommands.contains(where: { normalized($0.name).contains(needle) }) { return 4 }
        if normalized(row.summary).contains(needle) { return 5 }
        return row.subcommands.contains { subcommand in
            normalized(subcommand.usage ?? "").contains(needle)
                || normalized(subcommand.description ?? "").contains(needle)
        } ? 5 : nil
    }

    private static func closeDistance(for row: CommandBrowserRow, needle: String) -> Int? {
        ([row.canonicalName] + row.aliases).compactMap { boundedDamerauLevenshtein(
            Array(needle),
            Array(normalized($0)),
            maximumDistance: 2)
        }.min()
    }

    private static func stableRowOrder(_ lhs: CommandBrowserRow, _ rhs: CommandBrowserRow) -> Bool {
        let lhsSource = sourceOrder(lhs.source)
        let rhsSource = sourceOrder(rhs.source)
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        let lhsName = lhs.canonicalName.lowercased()
        let rhsName = rhs.canonicalName.lowercased()
        if lhsName != rhsName { return lhsName < rhsName }
        if lhs.canonicalName != rhs.canonicalName { return lhs.canonicalName < rhs.canonicalName }
        return lhs.rawSource < rhs.rawSource
    }

    private static func sourceOrder(_ source: CommandBrowserSource) -> Int {
        switch source {
        case .app: 0
        case .commands: 1
        case .skills: 2
        case .extensions: 3
        case .prompts: 4
        case .other: 5
        case .all: 6
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { character in
            character != ":" && character != "_" && character != "-"
        }
    }

    private static func hasWordBoundaryMatch(_ value: String, needle: String) -> Bool {
        var token = ""
        for character in value.lowercased() {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else {
                if normalized(token).hasPrefix(needle) { return true }
                token = ""
            }
        }
        return normalized(token).hasPrefix(needle)
    }

    private static func boundedDamerauLevenshtein(
        _ lhs: [Character],
        _ rhs: [Character],
        maximumDistance: Int
    ) -> Int? {
        guard abs(lhs.count - rhs.count) <= maximumDistance else { return nil }
        var previousPrevious = Array(0...rhs.count)
        var previous = Array(0...rhs.count)

        for lhsIndex in lhs.indices {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = lhsIndex + 1
            var minimum = current[0]
            for rhsIndex in rhs.indices {
                let substitution = previous[rhsIndex] + (lhs[lhsIndex] == rhs[rhsIndex] ? 0 : 1)
                var cost = min(previous[rhsIndex + 1] + 1, current[rhsIndex] + 1, substitution)
                if lhsIndex > 0, rhsIndex > 0,
                   lhs[lhsIndex] == rhs[rhsIndex - 1], lhs[lhsIndex - 1] == rhs[rhsIndex] {
                    cost = min(cost, previousPrevious[rhsIndex - 1] + 1)
                }
                current[rhsIndex + 1] = cost
                minimum = min(minimum, cost)
            }
            guard minimum <= maximumDistance else { return nil }
            previousPrevious = previous
            previous = current
        }
        return previous[rhs.count] <= maximumDistance ? previous[rhs.count] : nil
    }
}
