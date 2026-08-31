import OmpKit
import Testing
@testable import TenXApp

private let browserFixtureCommands = [
    AvailableSlashCommand(
        name: "model",
        description: "OMP model command",
        source: .builtin),
    AvailableSlashCommand(
        name: "compact",
        aliases: ["summarize"],
        description: "Compact the current session",
        inputHint: "[instructions]",
        source: .builtin),
    AvailableSlashCommand(
        name: "add-dir",
        description: "Add a working directory",
        source: .extensionCommand),
    AvailableSlashCommand(
        name: "skill:brainstorming",
        description: "Explore requirements before implementation",
        source: .skill),
    AvailableSlashCommand(
        name: "release-notes",
        description: "Draft release notes",
        source: .custom),
]

private func matchNames(_ query: String) -> [String] {
    CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: query,
        selectedSource: .all,
        mode: .activeIdle)
        .rows.map(\.canonicalName)
}

@Test func slashTriggerRequiresTheFirstNonWhitespaceCharacter() {
    #expect(CommandBrowserPresentation.parseDraft("/")?.query == "")
    #expect(CommandBrowserPresentation.parseDraft("  /model")?.query == "model")
    #expect(CommandBrowserPresentation.parseDraft("/skill:brainstorming plan it")?.arguments == "plan it")
    #expect(CommandBrowserPresentation.parseDraft("open /model") == nil)
    #expect(CommandBrowserPresentation.parseDraft("https://example.com") == nil)
    #expect(CommandBrowserPresentation.parseDraft("src/App/Thing.swift") == nil)
    #expect(CommandBrowserPresentation.parseDraft("hello\n/model") == nil)
    #expect(CommandBrowserPresentation.parseDraft("\n/model") == nil)
    #expect(CommandBrowserPresentation.parseDraft(" \t\n/model") == nil)
}

@Test func firstLineSlashCommandKeepsMultilineArguments() {
    let draft = CommandBrowserPresentation.parseDraft("/skill:brainstorming\nplan it")

    #expect(draft == ParsedSlashDraft(query: "skill:brainstorming", arguments: "plan it"))
}

@Test func browserMapsEveryKnownAndUnknownOMPSource() {
    #expect(CommandBrowserPresentation.source(for: .builtin) == .commands)
    #expect(CommandBrowserPresentation.source(for: .skill) == .skills)
    #expect(CommandBrowserPresentation.source(for: .extensionCommand) == .extensions)
    #expect(CommandBrowserPresentation.source(for: .custom) == .prompts)
    #expect(CommandBrowserPresentation.source(for: .mcpPrompt) == .prompts)
    #expect(CommandBrowserPresentation.source(for: .file) == .prompts)
    #expect(CommandBrowserPresentation.source(for: .other("future")) == .other)
}

@Test func appRowsReplaceSameNamedOMPRowsAndLeadStableRootOrder() {
    let rows = CommandBrowserPresentation.rows(commands: browserFixtureCommands, mode: .activeIdle)
    #expect(rows.prefix(3).map(\.canonicalName) == ["model", "effort", "fast"])
    #expect(rows.filter { $0.canonicalName == "model" }.count == 1)
    #expect(rows.dropFirst(3).map(\.source).starts(with: [.commands]))
}

@Test func appReplacementUsesCaseInsensitiveCanonicalEqualityOnly() {
    let rows = CommandBrowserPresentation.rows(commands: [
        AvailableSlashCommand(name: "model", source: .builtin),
        AvailableSlashCommand(name: "MODEL", source: .builtin),
        AvailableSlashCommand(name: "m:odel", source: .builtin),
        AvailableSlashCommand(name: "fa-st", source: .builtin),
    ], mode: .activeIdle)

    #expect(rows.map(\.canonicalName) == ["model", "effort", "fast", "fa-st", "m:odel"])
}

@Test func sameSourceCanonicalCaseTiesHaveInputIndependentOrder() {
    let forward = [
        AvailableSlashCommand(name: "alpha", source: .builtin),
        AvailableSlashCommand(name: "ALPHA", source: .builtin),
    ]
    let reverse = Array(forward.reversed())

    #expect(CommandBrowserPresentation.rows(commands: forward, mode: .activeIdle).map(\.canonicalName)
        == CommandBrowserPresentation.rows(commands: reverse, mode: .activeIdle).map(\.canonicalName))
}

@Test func browserMatchingUsesCanonicalAliasNamespaceAndSeparators() {
    #expect(matchNames("adddir") == ["add-dir"])
    #expect(matchNames("brainstorming") == ["skill:brainstorming"])
    #expect(matchNames("sum") == ["compact"])
}

@Test func rankingFollowsTheApprovedLadderAndAlphabeticalTies() {
    let commands = [
        AvailableSlashCommand(name: "zeta", description: "model guidance", source: .builtin),
        AvailableSlashCommand(name: "beta-model", source: .builtin),
        AvailableSlashCommand(name: "alpha-model", source: .builtin),
        AvailableSlashCommand(name: "modeling", source: .builtin),
        AvailableSlashCommand(name: "catalog", subcommands: [AvailableSlashSubcommand(name: "model")], source: .builtin),
        AvailableSlashCommand(name: "usage", subcommands: [AvailableSlashSubcommand(name: "help", usage: "model <id>")], source: .builtin),
    ]

    #expect(CommandBrowserPresentation.present(
        commands: commands,
        query: "model",
        selectedSource: .all,
        mode: .activeIdle).rows.map(\.canonicalName)
        == ["model", "modeling", "alpha-model", "beta-model", "catalog", "usage", "zeta"])
}

@Test func rowIdentityPreservesRawSourceAndCanonicalNameWithoutChangingAliasDisplay() {
    let commands = [
        AvailableSlashCommand(name: "same", aliases: ["shortcut"], source: .builtin),
        AvailableSlashCommand(name: "same", aliases: ["alternate"], source: .other("plugin")),
        AvailableSlashCommand(name: "", source: .builtin),
        AvailableSlashCommand(name: "same", source: .builtin),
    ]
    let rows = CommandBrowserPresentation.rows(commands: commands, mode: .activeIdle)

    #expect(rows.filter { $0.canonicalName == "same" }.map(\.id) == [
        CommandBrowserRowID(rawSource: "builtin", canonicalName: "same"),
        CommandBrowserRowID(rawSource: "plugin", canonicalName: "same"),
    ])
    #expect(rows.first { $0.canonicalName == "same" }?.aliases == ["shortcut"])
}

@Test func sourceFilteringAndAvailabilityAreDeterministic() {
    let newSession = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "",
        selectedSource: .all,
        mode: .newSession)
    #expect(Set(newSession.rows.map(\.source)).isSubset(of: [.app, .skills, .prompts]))
    #expect(newSession.sources.first { $0.id == .commands }?.message
        == "Start a session to use OMP commands.")
    #expect(CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "",
        selectedSource: .extensions,
        mode: .newSession).rows.isEmpty)
    #expect(CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "",
        selectedSource: .commands,
        mode: .unavailable).sources.first { $0.id == .commands }?.message != nil)
}

@Test func newSessionUnavailableSourcesKeepTheirLimitationWhileOtherSourcesMatch() {
    let commands = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "compact",
        selectedSource: .commands,
        mode: .newSession)
    let extensions = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "adddir",
        selectedSource: .extensions,
        mode: .newSession)

    for result in [commands, extensions] {
        #expect(result.rows.isEmpty)
        #expect(result.initialSelection == nil)
        #expect(result.heading == "Start a session to use OMP commands.")
    }
    #expect(CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "model",
        selectedSource: .all,
        mode: .newSession).rows.map(\.canonicalName) == ["model"])
    #expect(CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "brainstorming",
        selectedSource: .all,
        mode: .newSession).rows.map(\.canonicalName) == ["skill:brainstorming"])
    #expect(CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "release",
        selectedSource: .all,
        mode: .newSession).rows.map(\.canonicalName) == ["release-notes"])
}

@Test func emptyCatalogKeepsOnlyTheFixedAppRowsAndNoOtherSource() {
    let result = CommandBrowserPresentation.present(
        commands: [],
        query: "",
        selectedSource: .all,
        mode: .activeIdle)

    #expect(result.rows.map(\.canonicalName) == ["model", "effort", "fast"])
    #expect(!result.sources.contains { $0.id == .other })
}

@Test func streamingRowsExplainWhenEachCommandWillRun() {
    let rows = CommandBrowserPresentation.rows(commands: browserFixtureCommands, mode: .activeStreaming)
    #expect(rows.first?.executionNote == "Applies to the next request")
    #expect(rows.first { $0.source == .commands }?.executionNote == "Runs after the current response")
}

@Test func directNoMatchAndCloseMatchesHaveDifferentSelectionRules() {
    let noMatch = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "zzzz",
        selectedSource: .all,
        mode: .activeIdle)
    #expect(noMatch.heading == "No commands match “/zzzz”.")
    #expect(noMatch.rows.isEmpty)

    let close = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "modle",
        selectedSource: .all,
        mode: .activeIdle)
    #expect(close.heading == "Close results")
    #expect(close.rows.map(\.canonicalName).contains("model"))
    #expect(close.initialSelection == nil)
}

@Test func unavailableModeKeepsAppMatchesButDoesNotClaimMissingOMPMatches() {
    let compact = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "compact",
        selectedSource: .all,
        mode: .unavailable)
    let model = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "model",
        selectedSource: .all,
        mode: .unavailable)

    #expect(compact.rows.isEmpty)
    #expect(compact.heading == "Session commands unavailable")
    #expect(model.rows.map(\.canonicalName) == ["model"])
    #expect(model.heading == nil)
}

@Test func directResultsSelectFirstAndRetainOnlyExactStableIdentity() {
    let result = CommandBrowserPresentation.present(
        commands: browserFixtureCommands,
        query: "sum",
        selectedSource: .all,
        mode: .activeIdle)
    let compact = CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact")
    #expect(result.initialSelection == compact)
    #expect(CommandBrowserPresentation.retainedSelection(compact, in: result.rows) == compact)
    #expect(CommandBrowserPresentation.retainedSelection(
        CommandBrowserRowID(rawSource: "custom", canonicalName: "compact"),
        in: result.rows) == nil)
}
