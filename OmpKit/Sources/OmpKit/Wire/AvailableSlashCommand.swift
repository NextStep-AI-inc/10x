import Foundation

public enum AvailableSlashCommandSource: Sendable, Equatable, Hashable {
    case builtin
    case skill
    case extensionCommand
    case custom
    case mcpPrompt
    case file
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "builtin": self = .builtin
        case "skill": self = .skill
        case "extension": self = .extensionCommand
        case "custom": self = .custom
        case "mcp_prompt": self = .mcpPrompt
        case "file": self = .file
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .builtin: return "builtin"
        case .skill: return "skill"
        case .extensionCommand: return "extension"
        case .custom: return "custom"
        case .mcpPrompt: return "mcp_prompt"
        case .file: return "file"
        case .other(let value): return value
        }
    }
}

public struct AvailableSlashSubcommand: Sendable, Equatable, Hashable {
    public let name: String
    public let description: String?
    public let usage: String?

    public init(name: String, description: String? = nil, usage: String? = nil) {
        self.name = name
        self.description = description
        self.usage = usage
    }
}

public struct AvailableSlashCommand: Sendable, Equatable, Hashable {
    public let name: String
    public let aliases: [String]
    public let description: String?
    public let inputHint: String?
    public let subcommands: [AvailableSlashSubcommand]
    public let source: AvailableSlashCommandSource

    public init(
        name: String,
        aliases: [String] = [],
        description: String? = nil,
        inputHint: String? = nil,
        subcommands: [AvailableSlashSubcommand] = [],
        source: AvailableSlashCommandSource
    ) {
        self.name = name
        self.aliases = aliases
        self.description = description
        self.inputHint = inputHint
        self.subcommands = subcommands
        self.source = source
    }
}

public enum AvailableSlashCommandDecodingError: Error, Sendable, Equatable {
    case invalidSnapshot
}

public enum AvailableSlashCommandDecoder {
    public static func decodeSnapshot(_ value: JSONValue) throws -> [AvailableSlashCommand] {
        guard let commands = value["commands"]?.arrayValue else {
            throw AvailableSlashCommandDecodingError.invalidSnapshot
        }
        return commands.compactMap(decodeCommand)
    }

    private static func decodeCommand(_ value: JSONValue) -> AvailableSlashCommand? {
        guard let object = value.objectValue,
              let name = nonEmptyTrimmed(object["name"]?.stringValue),
              let sourceValue = nonEmptyTrimmed(object["source"]?.stringValue)
        else { return nil }

        let aliases = object["aliases"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        let description = trimmed(object["description"]?.stringValue)
        let inputHint = trimmed(object["input"]?["hint"]?.stringValue)
        let subcommands = object["subcommands"]?.arrayValue?.compactMap(decodeSubcommand) ?? []

        return AvailableSlashCommand(
            name: name,
            aliases: aliases,
            description: description,
            inputHint: inputHint,
            subcommands: subcommands,
            source: AvailableSlashCommandSource(rawValue: sourceValue))
    }

    private static func decodeSubcommand(_ value: JSONValue) -> AvailableSlashSubcommand? {
        guard let object = value.objectValue,
              let name = nonEmptyTrimmed(object["name"]?.stringValue)
        else { return nil }
        return AvailableSlashSubcommand(
            name: name,
            description: trimmed(object["description"]?.stringValue),
            usage: trimmed(object["usage"]?.stringValue))
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        trimmed(value)
    }
}
