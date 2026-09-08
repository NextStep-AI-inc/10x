import Testing
@testable import OmpKit

@Test func availableCommandsDecoderKeepsTheCompleteContract() throws {
    let snapshot: JSONValue = .object([
        "commands": .array([
            .object([
                "name": .string(" compact "),
                "aliases": .array([.string("summarize")]),
                "description": .string("  Compact the session  "),
                "input": .object(["hint": .string(" [instructions] ")]),
                "subcommands": .array([
                    .object([
                        "name": .string(" status "),
                        "description": .string(" Show compaction status "),
                        "usage": .string(" /compact status "),
                    ]),
                ]),
                "source": .string("builtin"),
            ]),
        ]),
    ])

    let commands = try AvailableSlashCommandDecoder.decodeSnapshot(snapshot)

    #expect(commands == [AvailableSlashCommand(
        name: "compact",
        aliases: ["summarize"],
        description: "Compact the session",
        inputHint: "[instructions]",
        subcommands: [AvailableSlashSubcommand(
            name: "status",
            description: "Show compaction status",
            usage: "/compact status",
        )],
        source: .builtin,
    )])
}

@Test func availableCommandsDecoderKeepsUnknownSources() throws {
    let snapshot: JSONValue = .object([
        "commands": .array([
            .object(["name": .string("pack"), "source": .string("remote_pack")]),
        ]),
    ])

    let command = try #require(try AvailableSlashCommandDecoder.decodeSnapshot(snapshot).first)
    #expect(command.source == .other("remote_pack"))
    #expect(command.source.rawValue == "remote_pack")
}

@Test func availableCommandsDecoderDropsMalformedSiblingsAndSubcommands() throws {
    let snapshot: JSONValue = .object([
        "commands": .array([
            .object(["source": .string("builtin")]),
            .object([
                "name": .string("brainstorming"),
                "source": .string("skill"),
                "subcommands": .array([
                    .object(["name": .string("resume")]),
                    .object(["description": .string("missing name")]),
                ]),
            ]),
        ]),
    ])

    let commands = try AvailableSlashCommandDecoder.decodeSnapshot(snapshot)

    #expect(commands == [AvailableSlashCommand(
        name: "brainstorming",
        subcommands: [AvailableSlashSubcommand(name: "resume")],
        source: .skill,
    )])
}

@Test func availableCommandsDecoderRejectsMalformedTopLevelPayload() {
    let snapshot: JSONValue = .object(["commands": .string("not an array")])

    do {
        _ = try AvailableSlashCommandDecoder.decodeSnapshot(snapshot)
        Issue.record("Expected malformed snapshot to throw")
    } catch let error as AvailableSlashCommandDecodingError {
        #expect(error == .invalidSnapshot)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
