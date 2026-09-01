import Foundation

struct CommandBrowserSourceAction: Equatable, Sendable {
    let name: String
    let source: CommandBrowserSource
}

enum CommandBrowserAccessibility {
    static func rowLabel(
        name: String,
        description: String,
        source: String,
        position: Int,
        count: Int,
        executionNote: String?
    ) -> String {
        [
            name,
            description,
            source,
            "\(position) of \(count)",
            executionNote,
        ]
        .compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: ", ")
    }

    static func sourceValue(count: Int) -> String {
        count == 1 ? "1 command" : "\(count) commands"
    }

    static func sourceLabel(_ source: CommandBrowserSource) -> String {
        source.rawValue
    }

    static func sourceSelectionAnnouncement(
        source: CommandBrowserSource,
        count: Int,
        message: String?
    ) -> String {
        [
            source.rawValue,
            sourceValue(count: count),
            message,
        ]
        .compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: ", ")
    }

    static func catalogLoadedAnnouncement(count: Int) -> String {
        count == 1 ? "1 command loaded" : "\(count) commands loaded"
    }

    static func rootSourceActions(_ sources: [CommandBrowserSourceItem]) -> [CommandBrowserSourceAction] {
        sources.map { item in
            CommandBrowserSourceAction(name: item.id.rawValue, source: item.id)
        }
    }

    static func helpText() -> String {
        "Type to filter. Up and Down move results. Control Tab changes source. Command 1 through Command 7 selects a source. Enter opens or runs. Tab completes. Escape closes."
    }
}
