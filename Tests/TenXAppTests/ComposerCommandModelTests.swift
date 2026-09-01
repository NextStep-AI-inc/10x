import AppKit
import Foundation
import OmpKit
import SwiftUI
import Testing
@testable import TenXApp

@Test func commandBrowserKeyRoutingCoversTheWholeModalWithoutAPointer() {
    func route(
        _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> ComposerCommandKeyAction? {
        ComposerCommandKeyRouting.route(key, modifiers: modifiers)
    }

    #expect(route(.upArrow, modifiers: []) == .move(.previous))
    #expect(route(.downArrow, modifiers: []) == .move(.next))
    #expect(route(.home, modifiers: []) == .move(.first))
    #expect(route(.end, modifiers: []) == .move(.last))
    #expect(route(.pageUp, modifiers: []) == .move(.pagePrevious))
    #expect(route(.pageDown, modifiers: []) == .move(.pageNext))
    #expect(route(.tab, modifiers: [.control]) == .cycle(.forward))
    #expect(route(.tab, modifiers: [.control, .option]) == nil)
    #expect(route(.tab, modifiers: [.control, .command]) == nil)
    #expect(route(.tab, modifiers: [.control, .shift]) == .cycle(.backward))
    #expect(route(.tab, modifiers: [.control, .shift, .option]) == nil)
    #expect(route(.tab, modifiers: [.control, .shift, .command]) == nil)
    #expect(route(KeyEquivalent("3"), modifiers: [.command]) == .sourceIndex(3))
    #expect(route(.return, modifiers: []) == .activate)
    #expect(route(.tab, modifiers: []) == .complete)
    #expect(route(.escape, modifiers: []) == .back)
    #expect(route(.leftArrow, modifiers: []) == nil)
}

@Test func commandBrowserComposerQueryStateKeepsRootAndNativeModelSearchSeparate() {
    #expect(ComposerCommandQueryRouting.query(draft: "/modxyz", route: .root) == "modxyz")
    #expect(ComposerCommandQueryRouting.query(draft: "  /model", route: .root) == "model")
    #expect(ComposerCommandQueryRouting.query(draft: "/model", route: .native(.model)) == "")
    #expect(ComposerCommandQueryRouting.query(draft: "/effort", route: .native(.effort)) == "effort")
}

@Test func commandBrowserNewSessionNoMatchActivationUsesTheExistingSendPath() {
    #expect(ComposerCommandActivationRouting.action(
        isNewSession: true,
        hasVisibleRows: false,
        hasSelection: false) == .sendUnchangedDraft)
    #expect(ComposerCommandActivationRouting.action(
        isNewSession: true,
        hasVisibleRows: true,
        hasSelection: false) == .useCommandModel)
    #expect(ComposerCommandActivationRouting.action(
        isNewSession: false,
        hasVisibleRows: false,
        hasSelection: false) == .useCommandModel)
}

@Test func commandBrowserComposerFocusReturnsOnlyWhenTheEditorOwnsInput() {
    #expect(!ComposerCommandFocusRouting.shouldRestoreEditorFocus(
        effect: .none,
        isPresented: true,
        route: .native(.model)))
    #expect(!ComposerCommandFocusRouting.shouldRestoreEditorFocus(
        effect: .keepDraft,
        isPresented: true,
        route: .native(.model)))
    #expect(ComposerCommandFocusRouting.shouldRestoreEditorFocus(
        effect: .keepDraft,
        isPresented: true,
        route: .root))
    #expect(ComposerCommandFocusRouting.shouldRestoreEditorFocus(
        effect: .replaceDraft("/compact "),
        isPresented: true,
        route: .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact"))))
    #expect(ComposerCommandFocusRouting.shouldRestoreEditorFocus(
        effect: .executed,
        isPresented: false,
        route: .root))
}

@Test func commandBrowserExitCommandUsesCommandSpecificDismissal() {
    #expect(ComposerCommandDismissalRouting.action(for: .commands) == .dismissCommands)
    #expect(ComposerCommandDismissalRouting.action(for: .model) == .hideFlyoutOnly)
    #expect(ComposerCommandDismissalRouting.action(for: .project) == .hideFlyoutOnly)
    #expect(ComposerCommandDismissalRouting.action(for: nil) == .hideFlyoutOnly)
}

@Test func commandBrowserKeyboardMonitorTranslatesRealAppKitEvents() {
    #expect(CommandBrowserKeyboardEventRouting.action(for: keyDown(keyCode: 125)) == .move(.next))
    #expect(CommandBrowserKeyboardEventRouting.action(for: keyDown(keyCode: 48, characters: "\t", modifiers: .control)) == .cycle(.forward))
    #expect(CommandBrowserKeyboardEventRouting.action(for: keyDown(keyCode: 48, characters: "\t", modifiers: [.control, .shift])) == .cycle(.backward))
    #expect(CommandBrowserKeyboardEventRouting.action(for: keyDown(keyCode: 20, characters: "3", modifiers: .command)) == .sourceIndex(3))
    #expect(CommandBrowserKeyboardEventRouting.action(for: keyDown(keyCode: 76)) == .activate)
    #expect(CommandBrowserKeyboardEventRouting.action(for: keyDown(keyCode: 125, modifiers: .option)) == nil)
}

@Test func commandBrowserKeyboardCapturePolicyFollowsTheCurrentRoute() {
    let rowID = CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact")

    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.move(.next), route: .root))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.sourceIndex(3), route: .root))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.activate, route: .root))
    #expect(!CommandBrowserKeyboardCapturePolicy.shouldCapture(.move(.next), route: .arguments(rowID)))
    #expect(!CommandBrowserKeyboardCapturePolicy.shouldCapture(.complete, route: .arguments(rowID)))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.activate, route: .arguments(rowID)))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.back, route: .arguments(rowID)))
    #expect(!CommandBrowserKeyboardCapturePolicy.shouldCapture(.move(.next), route: .native(.model)))
    #expect(!CommandBrowserKeyboardCapturePolicy.shouldCapture(.activate, route: .native(.model)))
    #expect(!CommandBrowserKeyboardCapturePolicy.shouldCapture(.back, route: .native(.model)))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.cycle(.forward), route: .native(.model)))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.move(.next), route: .subcommands(rowID)))
    #expect(CommandBrowserKeyboardCapturePolicy.shouldCapture(.sourceIndex(3), route: .subcommands(rowID)))
}

@Test func commandBrowserKeyboardMonitorConsumesOnlyHandledCommandEvents() {
    var handled: [ComposerCommandKeyAction] = []
    let down = keyDown(keyCode: 125)
    let left = keyDown(keyCode: 123)
    let argumentReturn = keyDown(keyCode: 36, characters: "\r")
    let rowID = CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact")

    #expect(CommandBrowserKeyboardEventRouting.result(for: down, route: .root) { action in
        handled.append(action)
        return true
    } == .consume)
    #expect(handled == [.move(.next)])
    #expect(CommandBrowserKeyboardEventRouting.result(for: left, route: .root) { _ in true } == .pass)
    #expect(CommandBrowserKeyboardEventRouting.result(for: down, route: .arguments(rowID)) { _ in true } == .pass)
    #expect(CommandBrowserKeyboardEventRouting.result(for: argumentReturn, route: .arguments(rowID)) { _ in false } == .pass)
    #expect(CommandBrowserKeyboardEventRouting.result(for: argumentReturn, route: .arguments(rowID)) { _ in true } == .consume)
}

@MainActor
@Test func commandModelOpensOnlyForAValidSlashDraft() async {
    let catalog = CommandModelCatalog()
    let controls = ComposerControlsModel(
        catalog: catalog,
        defaults: CommandModelDefaults())
    let model = ComposerCommandModel(catalog: catalog, controls: controls) { _, _ in }

    #expect(model.updateDraft("hello /model") == false)
    #expect(model.isPresented == false)
    #expect(model.updateDraft(" /"))
    #expect(model.isPresented)
    #expect(model.selectedRowID == CommandBrowserRowID(rawSource: "app", canonicalName: "model"))
}

@MainActor
@Test func commandModelNavigatesRowsAndSourcesWithoutChangingTheDraft() async {
    let catalog = CommandModelCatalog(commands: commandModelCommands)
    let model = commandModel(catalog: catalog)
    await Task.yield()
    #expect(model.updateDraft("/"))
    model.selectSource(.app)
    model.moveSelection(.last)
    #expect(model.highlightedRow?.canonicalName == "fast")
    model.moveSelection(.next)
    #expect(model.highlightedRow?.canonicalName == "model")
    model.moveSelection(.last)
    model.moveSelection(.pagePrevious)
    #expect(model.highlightedRow != nil)
    model.selectVisibleSource(at: 2)
    #expect(model.selectedSource == .app)
    model.selectVisibleSource(at: 99)
    #expect(model.selectedSource == .app)
}

@MainActor
@Test func commandModelStagesCanonicalArgumentsAndExecutesOnlyFromAnActiveSession() async {
    let catalog = CommandModelCatalog(commands: commandModelCommands)
    let model = commandModel(catalog: catalog)
    let session = CommandModelSession(state: .idle, catalog: .available(commandModelCommands))
    model.attachActiveSession(session)
    #expect(model.updateDraft("  /alias\nkept"))
    model.highlight(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact"))
    #expect(model.complete() == .replaceDraft("/compact\nkept"))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact")))
    #expect(await model.activate() == .executed)
    #expect(session.sent == ["/compact\nkept"])
}

@MainActor
@Test func commandModelRoutesNativeCommandsAndDoesNotExecuteThem() async {
    let model = commandModel(catalog: CommandModelCatalog())
    #expect(model.updateDraft("/model"))
    #expect(await model.activate() == .keepDraft)
    #expect(model.route == .native(.model))
}

@MainActor
@Test func commandModelSupportsHomeEndPageAndSourceCycling() async {
    let model = commandModel(catalog: CommandModelCatalog())
    await Task.yield()
    #expect(model.updateDraft("/"))
    model.moveSelection(.last)
    let last = model.selectedRowID
    model.moveSelection(.first)
    #expect(model.selectedRowID != last)
    model.moveSelection(.pageNext)
    #expect(model.selectedRowID == last)
    model.cycleSource(.forward)
    #expect(model.selectedSource == .app)
    model.cycleSource(.backward)
    #expect(model.selectedSource == .all)
}

@MainActor
@Test func commandModelExecutesTypedCloseResultWithoutCorrectingIt() async {
    let model = commandModel(catalog: CommandModelCatalog())
    let session = CommandModelSession(state: .streaming, catalog: .available(commandModelCommands))
    model.attachActiveSession(session)
    #expect(model.updateDraft(" /compct one\ntwo"))
    #expect(model.selectedRowID == nil)
    #expect(await model.activate() == .executed)
    #expect(session.sent == ["/compct one\ntwo"])
}

@MainActor
@Test func commandModelDoesNotSendTypedOMPCommandWhileCatalogIsUnavailable() async {
    let catalog = CommandModelCatalog()
    let model = commandModel(catalog: catalog)
    let session = CommandModelSession(state: .idle, catalog: .unavailable)
    model.attachActiveSession(session)

    #expect(model.updateDraft("/model"))
    #expect(model.visibleRows.map(\.canonicalName) == ["model"])
    #expect(model.sources.first(where: { $0.id == .commands })?.message == "Model, Effort, and Fast remain available. Retry after the session reconnects.")
    #expect(await model.activate() == .keepDraft)
    #expect(model.route == .native(.model))
    #expect(model.updateDraft("/compact"))
    #expect(await model.activate() == .none)
    #expect(session.sent.isEmpty)
}

@MainActor
@Test func commandModelReturnsFromChildAndDismissesFromRoot() async {
    let model = commandModel(catalog: CommandModelCatalog())
    let session = CommandModelSession(state: .idle, catalog: .available(commandModelCommands))
    model.attachActiveSession(session)
    await Task.yield()
    #expect(model.updateDraft("/compact"))
    model.highlight(model.visibleRows.first { $0.canonicalName == "compact" }?.id)
    #expect(model.complete() == .replaceDraft("/compact "))
    #expect(model.back() == .keepDraft)
    #expect(model.route == .root)
    #expect(model.back() == .dismiss)
    #expect(!model.isPresented)
}

@MainActor
@Test func commandModelAllowsOnlySkillsForNewSessions() async {
    var started: [String] = []
    let catalog = CommandModelCatalog()
    let model = ComposerCommandModel(catalog: catalog, controls: ComposerControlsModel(catalog: catalog, defaults: CommandModelDefaults())) {
        text, _ in started.append(text)
    }
    for _ in 0..<8 { await Task.yield() }
    #expect(model.updateDraft("/skill:write"))
    model.highlight(model.visibleRows.first { $0.canonicalName == "skill:write" }?.id)
    #expect(await model.activate() == .replaceDraft("/skill:write "))
    #expect(await model.activate() == .executed)
    #expect(started == ["/skill:write "])
    #expect(model.updateDraft("/compact"))
    model.highlight(model.visibleRows.first { $0.canonicalName == "compact" }?.id)
    #expect(await model.activate() == .none)
}

@MainActor
@Test func commandModelMovesAtEveryBoundaryAndPagesByEightRows() async {
    let commands = (0..<11).map { AvailableSlashCommand(name: "command-\(String(format: "%02d", $0))", source: .builtin) }
    let model = commandModel(catalog: CommandModelCatalog(commands: commands))
    let session = CommandModelSession(state: .idle, catalog: .available(commands))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/"))
    model.moveSelection(.first)
    #expect(model.highlightedRow?.canonicalName == "model")
    model.moveSelection(.previous)
    #expect(model.highlightedRow?.canonicalName == "command-10")
    model.moveSelection(.next)
    #expect(model.highlightedRow?.canonicalName == "model")
    model.moveSelection(.last)
    #expect(model.highlightedRow?.canonicalName == "command-10")
    model.moveSelection(.next)
    #expect(model.highlightedRow?.canonicalName == "model")
    model.moveSelection(.pageNext)
    #expect(model.highlightedRow?.canonicalName == "command-05")
    model.moveSelection(.pagePrevious)
    #expect(model.highlightedRow?.canonicalName == "model")
    model.moveSelection(.pagePrevious)
    #expect(model.highlightedRow?.canonicalName == "model")
    model.moveSelection(.last)
    model.moveSelection(.pageNext)
    #expect(model.highlightedRow?.canonicalName == "command-10")
}

@MainActor
@Test func commandModelCyclesVisibleSourcesAndUsesEachSourceInitialSelection() async {
    let commands = commandModelCommands + [
        AvailableSlashCommand(name: "extension:run", source: .extensionCommand),
        AvailableSlashCommand(name: "prompt:review", source: .mcpPrompt),
    ]
    let model = commandModel(catalog: CommandModelCatalog(commands: commands))
    let session = CommandModelSession(state: .idle, catalog: .available(commands))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/"))
    #expect(model.sources.map(\.id) == [.all, .app, .commands, .skills, .extensions, .prompts])
    model.cycleSource(.backward)
    #expect(model.selectedSource == .prompts)
    #expect(model.highlightedRow?.canonicalName == "prompt:review")
    model.cycleSource(.forward)
    #expect(model.selectedSource == .all)
    model.selectVisibleSource(at: 4)
    #expect(model.selectedSource == .skills)
    #expect(model.highlightedRow?.canonicalName == "skill:write")
    model.selectVisibleSource(at: 0)
    model.selectVisibleSource(at: 99)
    #expect(model.selectedSource == .skills)
}

@MainActor
@Test func commandModelCompletesCanonicalCommandsWithoutSending() async {
    let commands = commandModelCommands + [
        AvailableSlashCommand(name: "subcommand", aliases: ["sub"], subcommands: [AvailableSlashSubcommand(name: "one")], source: .builtin),
        AvailableSlashCommand(name: "prompt:review", source: .mcpPrompt),
    ]
    let model = commandModel(catalog: CommandModelCatalog(commands: commands))
    let session = CommandModelSession(state: .idle, catalog: .available(commands))
    model.attachActiveSession(session)

    #expect(model.updateDraft(" /alias\nnotes"))
    model.highlight(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact"))
    #expect(model.complete() == .replaceDraft("/compact\nnotes"))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact")))
    #expect(session.sent.isEmpty)

    #expect(model.updateDraft("/sub"))
    model.highlight(CommandBrowserRowID(rawSource: "builtin", canonicalName: "subcommand"))
    #expect(model.complete() == .replaceDraft("/subcommand "))
    #expect(model.route == .subcommands(CommandBrowserRowID(rawSource: "builtin", canonicalName: "subcommand")))
    #expect(session.sent.isEmpty)

    #expect(model.updateDraft("/skill:write"))
    model.highlight(CommandBrowserRowID(rawSource: "skill", canonicalName: "skill:write"))
    #expect(model.complete() == .replaceDraft("/skill:write "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "skill", canonicalName: "skill:write")))
    #expect(session.sent.isEmpty)

    #expect(model.updateDraft("/prompt:review"))
    model.highlight(CommandBrowserRowID(rawSource: "mcp_prompt", canonicalName: "prompt:review"))
    #expect(model.complete() == .replaceDraft("/prompt:review "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "mcp_prompt", canonicalName: "prompt:review")))
    #expect(session.sent.isEmpty)
}

@MainActor
@Test func commandModelKeepsStagedSkillAndPromptArgumentsWhenComposerObserverSeesEdits() async {
    let cases = [
        AvailableSlashCommand(name: "skill:write", source: .skill),
        AvailableSlashCommand(name: "prompt:review", source: .mcpPrompt),
    ]
    for command in cases {
        let session = CommandModelSession(state: .idle, catalog: .available([command]))
        let model = commandModel(catalog: CommandModelCatalog(commands: [command]))
        model.attachActiveSession(session)
        let rowID = CommandBrowserRowID(rawSource: command.source.rawValue, canonicalName: command.name)

        #expect(model.updateDraft("/\(command.name)"))
        #expect(await model.activate() == .replaceDraft("/\(command.name) "))
        #expect(model.route == .arguments(rowID))
        #expect(model.updateDraft("/\(command.name) draft the spec"))
        #expect(model.route == .arguments(rowID))
        #expect(await model.activate() == .executed)
        #expect(session.sent == ["/\(command.name) draft the spec"])
    }
}

@MainActor
@Test func commandModelKeepsSelectedSubcommandWhenComposerObserverSeesArgumentEdits() async {
    let child = AvailableSlashSubcommand(name: "child", usage: "child <file>")
    let parent = AvailableSlashCommand(name: "parent", subcommands: [child], source: .builtin)
    let session = CommandModelSession(state: .idle, catalog: .available([parent]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.selectSubcommand(named: "child") == .replaceDraft("/parent child "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.updateDraft("/parent child foo"))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.selectedSubcommandUsage == "child <file>")
    #expect(await model.activate() == .executed)
    #expect(session.sent == ["/parent child foo"])
}

@MainActor
@Test func commandModelReturnsToRootWhenComposerObserverSeesAChangedStagedCommand() async {
    let commands = [
        AvailableSlashCommand(name: "compact", inputHint: "[note]", source: .builtin),
        AvailableSlashCommand(name: "skill:write", source: .skill),
    ]
    let session = CommandModelSession(state: .idle, catalog: .available(commands))
    let model = commandModel(catalog: CommandModelCatalog(commands: commands))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/skill:write"))
    #expect(await model.activate() == .replaceDraft("/skill:write "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "skill", canonicalName: "skill:write")))
    #expect(model.updateDraft("/compact notes"))
    #expect(model.route == .root)
    #expect(model.selectedSubcommandUsage == nil)
    #expect(model.highlightedRow?.canonicalName == "compact")
}

@MainActor
@Test func commandModelReturnsToRootWhenComposerObserverSeesAChangedSelectedSubcommand() async {
    let child = AvailableSlashSubcommand(name: "child", usage: "child <file>")
    let parent = AvailableSlashCommand(name: "parent", subcommands: [child], source: .builtin)
    let session = CommandModelSession(state: .idle, catalog: .available([parent]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.selectSubcommand(named: "child") == .replaceDraft("/parent child "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.updateDraft("/parent other foo"))
    #expect(model.route == .root)
    #expect(model.selectedSubcommandUsage == nil)
    #expect(session.sent.isEmpty)
}

@MainActor
@Test func commandModelSelectsHighlightedSubcommandsBeforeSendingArguments() async {
    let parent = AvailableSlashCommand(
        name: "parent",
        subcommands: [
            AvailableSlashSubcommand(name: "alpha"),
            AvailableSlashSubcommand(name: "beta"),
            AvailableSlashSubcommand(name: "gamma"),
        ],
        source: .builtin)
    let session = CommandModelSession(state: .idle, catalog: .available([parent]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.route == .subcommands(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.highlightedSubcommandName == "alpha")
    model.moveSubcommandSelection(.next)
    #expect(model.highlightedSubcommandName == "beta")
    model.moveSubcommandSelection(.last)
    #expect(model.highlightedSubcommandName == "gamma")
    model.moveSubcommandSelection(.next)
    #expect(model.highlightedSubcommandName == "alpha")
    model.moveSubcommandSelection(.pageNext)
    #expect(model.highlightedSubcommandName == "gamma")
    model.moveSubcommandSelection(.pagePrevious)
    #expect(model.highlightedSubcommandName == "alpha")
    #expect(model.complete() == .replaceDraft("/parent alpha "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.updateDraft("/parent alpha foo"))
    #expect(await model.activate() == .executed)
    #expect(session.sent == ["/parent alpha foo"])
}

@MainActor
@Test func commandModelStagesAndExecutesOnlyAnAdvertisedSubcommand() async {
    let child = AvailableSlashSubcommand(name: "child", usage: "child <file>")
    let parent = AvailableSlashCommand(name: "parent", subcommands: [child], source: .builtin)
    let session = CommandModelSession(state: .idle, catalog: .available([parent]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.selectSubcommand(named: "missing") == .none)
    #expect(model.route == .subcommands(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.selectSubcommand(named: "child") == .replaceDraft("/parent child "))
    #expect(model.route == .arguments(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    #expect(model.selectedSubcommandUsage == "child <file>")
    #expect(await model.activate() == .executed)
    #expect(session.sent == ["/parent child "])
}

@MainActor
@Test func commandModelRetainsAndRehomesHighlightedSubcommandAcrossCatalogUpdates() async {
    let alpha = AvailableSlashSubcommand(name: "alpha")
    let beta = AvailableSlashSubcommand(name: "beta")
    let gamma = AvailableSlashSubcommand(name: "gamma")
    let session = StreamingCommandSession(
        state: .idle,
        catalog: .available([AvailableSlashCommand(name: "parent", subcommands: [alpha, beta, gamma], source: .builtin)]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [
        AvailableSlashCommand(name: "parent", subcommands: [alpha, beta, gamma], source: .builtin),
    ]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    model.moveSubcommandSelection(.next)
    #expect(model.highlightedSubcommandName == "beta")
    session.yield(.available([AvailableSlashCommand(name: "parent", subcommands: [gamma, beta], source: .builtin)]))
    #expect(await eventually { model.highlightedSubcommandName == "beta" })
    session.yield(.available([AvailableSlashCommand(name: "parent", subcommands: [gamma], source: .builtin)]))
    #expect(await eventually { model.highlightedSubcommandName == "gamma" })
    session.yield(.available([AvailableSlashCommand(name: "parent", subcommands: [], source: .builtin)]))
    #expect(await eventually { model.route == .root })
    #expect(model.inlineMessage == "This command is no longer available.")
}

@MainActor
@Test func commandModelSourceSwitchesFromChildRoutesViaRoot() async {
    let parent = AvailableSlashCommand(
        name: "parent",
        subcommands: [AvailableSlashSubcommand(name: "child")],
        source: .builtin)
    let skill = AvailableSlashCommand(name: "parent-helper", source: .skill)
    let session = CommandModelSession(state: .idle, catalog: .available([parent, skill]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent, skill]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.route == .subcommands(CommandBrowserRowID(rawSource: "builtin", canonicalName: "parent")))
    model.selectVisibleSource(at: 4)
    #expect(model.route == .root)
    #expect(model.selectedSource == .skills)
    #expect(model.highlightedRow?.canonicalName == "parent-helper")
}

@MainActor
@Test func commandModelDoesNotExecuteAnAdvertisedChildRemovedByCatalogUpdate() async {
    let child = AvailableSlashSubcommand(name: "child", usage: "child <file>")
    let parent = AvailableSlashCommand(name: "parent", subcommands: [child], source: .builtin)
    let parentWithoutChild = AvailableSlashCommand(name: "parent", source: .builtin)
    for _ in 0..<100 {
        let session = StreamingCommandSession(state: .idle, catalog: .available([parent]))
        let model = commandModel(catalog: CommandModelCatalog(commands: [parent]))
        model.attachActiveSession(session)

        #expect(model.updateDraft("/parent"))
        #expect(await model.activate() == .replaceDraft("/parent "))
        #expect(model.selectSubcommand(named: "child") == .replaceDraft("/parent child "))
        session.yield(.available([parentWithoutChild]))
        #expect(await eventually { model.route == .root })
        #expect(model.inlineMessage == "This command is no longer available.")
        #expect(await model.activate() == .none)
        #expect(session.sent.isEmpty)
    }
}

@MainActor
@Test func commandModelRecoversFromRemovedChildAfterRootNavigation() async {
    let child = AvailableSlashSubcommand(name: "child")
    let parent = AvailableSlashCommand(name: "parent", subcommands: [child], source: .builtin)
    let parentWithoutChild = AvailableSlashCommand(name: "parent", source: .builtin)
    let parentSafe = AvailableSlashCommand(name: "parentSafe", source: .builtin)
    let parentSafeID = CommandBrowserRowID(rawSource: "builtin", canonicalName: "parentSafe")
    let session = StreamingCommandSession(state: .idle, catalog: .available([parent, parentSafe]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent, parentSafe]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.selectSubcommand(named: "child") == .replaceDraft("/parent child "))
    session.yield(.available([parentWithoutChild, parentSafe]))
    #expect(await eventually { model.route == .root })
    #expect(await model.activate() == .none)
    #expect(model.inlineMessage == "This command is no longer available.")

    model.highlight(parentSafeID)
    #expect(await model.activate() == .executed)
    #expect(model.inlineMessage == nil)
    #expect(session.sent == ["/parentSafe child "])
}

@MainActor
@Test func commandModelRecoversFromRemovedChildAfterSourceSwitch() async {
    let child = AvailableSlashSubcommand(name: "child")
    let parent = AvailableSlashCommand(name: "parent", subcommands: [child], source: .builtin)
    let parentWithoutChild = AvailableSlashCommand(name: "parent", source: .builtin)
    let extensionParent = AvailableSlashCommand(name: "parent", source: .extensionCommand)
    let session = StreamingCommandSession(state: .idle, catalog: .available([parent, extensionParent]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [parent, extensionParent]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/parent "))
    #expect(model.selectSubcommand(named: "child") == .replaceDraft("/parent child "))
    session.yield(.available([parentWithoutChild, extensionParent]))
    #expect(await eventually { model.route == .root })
    #expect(await model.activate() == .none)

    model.selectSource(.extensions)
    #expect(model.inlineMessage == nil)
    #expect(await model.activate() == .executed)
    #expect(session.sent == ["/parent child "])
}

@MainActor
@Test func commandModelPreservesNativeCommandRemaindersOnSuccess() async {
    let first = commandModelInfo(id: "one")
    let second = commandModelInfo(id: "two")
    let catalog = ControlsCommandCatalog(models: [first, second], selected: first)
    let controls = ComposerControlsModel(catalog: catalog, defaults: RecordingCommandDefaults())
    await controls.refresh(authenticatedProviderIDs: ["test"], projectURL: nil)
    let model = ComposerCommandModel(catalog: catalog, controls: controls) { _, _ in
        Issue.record("Native mutations must not start a session.")
    }

    #expect(model.updateDraft("/model\nkeep this prompt"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyModel(second) == .replaceDraft("keep this prompt"))

    #expect(model.updateDraft("/effort body"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyEffort("high") == .replaceDraft("body"))

    #expect(model.updateDraft("/fast"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyFast(true) == .replaceDraft(""))
}

@MainActor
@Test func commandModelRetainsOrRehomesSelectionWhenCatalogReplacesRows() async {
    let first = AvailableSlashCommand(name: "first", source: .builtin)
    let selected = AvailableSlashCommand(name: "selected", source: .builtin)
    let last = AvailableSlashCommand(name: "last", source: .builtin)
    let catalog = StreamingCommandCatalog(initial: .available([first, selected, last]))
    let model = commandModel(catalog: catalog)
    let session = StreamingCommandSession(state: .idle, catalog: .available([first, selected, last]))
    model.attachActiveSession(session)
    #expect(await eventually { model.updateDraft("/") && model.visibleRows.contains { $0.canonicalName == "selected" } })
    model.highlight(CommandBrowserRowID(rawSource: "builtin", canonicalName: "selected"))
    session.yield(.available([first, selected]))
    #expect(await eventually { model.highlightedRow?.canonicalName == "selected" })
    session.yield(.available([first, last]))
    #expect(await eventually { model.highlightedRow?.canonicalName == "last" })
}

@MainActor
@Test func commandModelReturnsUnavailableChildToRootWithExactMessage() async {
    let command = AvailableSlashCommand(name: "compact", inputHint: "[note]", source: .builtin)
    let model = commandModel(catalog: CommandModelCatalog(commands: [command]))
    let session = StreamingCommandSession(state: .idle, catalog: .available([command]))
    model.attachActiveSession(session)
    #expect(model.updateDraft("/compact"))
    model.highlight(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact"))
    #expect(model.complete() == .replaceDraft("/compact "))
    session.yield(.available([]))
    #expect(await eventually { model.route == .root })
    #expect(model.inlineMessage == "This command is no longer available.")
}

@MainActor
@Test func commandModelRoutesNativeBackAndDismissalTransitions() async {
    let model = commandModel(catalog: CommandModelCatalog())
    for command in AppCommand.allCases {
        #expect(model.updateDraft("/\(command.rawValue)"))
        #expect(await model.activate() == .keepDraft)
        #expect(model.route == .native(command))
        #expect(model.back() == .keepDraft)
        #expect(model.route == .root)
    }
    #expect(model.dismiss() == .dismiss)
    #expect(!model.isPresented)
    #expect(model.selectedSource == .all)
    #expect(model.selectedRowID == nil)
}

@MainActor
@Test func commandModelExecutesCanonicalTextExactlyOnceForIdleAndStreamingSessions() async {
    for state in [SessionRuntimeState.idle, .streaming] {
        let session = CommandModelSession(state: state, catalog: .available(commandModelCommands))
        let model = commandModel(catalog: CommandModelCatalog())
        model.attachActiveSession(session)
        #expect(model.updateDraft(" /alias\nbody"))
        model.highlight(CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact"))
        #expect(await model.activate() == .replaceDraft("/compact\nbody"))
        #expect(await model.activate() == .executed)
        #expect(session.sent == ["/compact\nbody"])
    }
}

@MainActor
@Test func commandModelStartsOnlySkillsAndPromptsForNewSessionsWithAttachments() async {
    let skill = AvailableSlashCommand(name: "skill:write", source: .skill)
    let prompt = AvailableSlashCommand(name: "prompt:review", source: .mcpPrompt)
    let attachment = ComposerAttachment(name: "proof.png", data: Data([1]), mimeType: "image/png", pixelWidth: 1, pixelHeight: 1)
    var starts: [(String, [ComposerAttachment])] = []
    let catalog = CommandModelCatalog(commands: [skill, prompt])
    let model = ComposerCommandModel(catalog: catalog, controls: ComposerControlsModel(catalog: catalog, defaults: CommandModelDefaults())) {
        starts.append(($0, $1))
    }
    #expect(await eventually { model.updateDraft("/") && model.visibleRows.count == 5 })

    for (name, source) in [("skill:write", "skill"), ("prompt:review", "mcp_prompt")] {
        #expect(model.updateDraft("/\(name)"))
        model.highlight(CommandBrowserRowID(rawSource: source, canonicalName: name))
        #expect(await model.activate(attachments: [attachment]) == .replaceDraft("/\(name) "))
        #expect(await model.activate(attachments: [attachment]) == .executed)
    }
    #expect(starts.map(\.0) == ["/skill:write ", "/prompt:review "])
    #expect(starts.allSatisfy { $0.1.map(\.id) == [attachment.id] })
}

@MainActor
@Test func commandModelNeverStartsNewSessionsForTypedCommandsOrExtensions() async {
    let commands = [
        AvailableSlashCommand(name: "compact", source: .builtin),
        AvailableSlashCommand(name: "extension:run", source: .extensionCommand),
    ]
    var starts: [String] = []
    let catalog = CommandModelCatalog(commands: commands)
    let model = ComposerCommandModel(catalog: catalog, controls: ComposerControlsModel(catalog: catalog, defaults: CommandModelDefaults())) {
        text, _ in starts.append(text)
    }
    #expect(await eventually { model.updateDraft("/compact") })
    #expect(await model.activate() == .none)
    #expect(model.updateDraft("/extension:run"))
    #expect(await model.activate() == .none)
    #expect(starts.isEmpty)
}

@MainActor
@Test func commandModelAppliesNativeMutationsOnceAndKeepsFailuresInline() async {
    let first = commandModelInfo(id: "one")
    let second = commandModelInfo(id: "two")
    let catalog = ControlsCommandCatalog(models: [first, second], selected: first)
    let defaults = RecordingCommandDefaults()
    let controls = ComposerControlsModel(catalog: catalog, defaults: defaults)
    await controls.refresh(authenticatedProviderIDs: ["test"], projectURL: nil)
    let model = ComposerCommandModel(catalog: catalog, controls: controls) { _, _ in
        Issue.record("Native controls must not start a session.")
    }

    #expect(model.updateDraft("/model"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyModel(second) == .replaceDraft(""))
    #expect(await defaults.modelCalls.count == 1)
    #expect(await defaults.modelCalls.first?.0 == "test")
    #expect(await defaults.modelCalls.first?.1 == "two")
    #expect(!model.isPresented)

    #expect(model.updateDraft("/effort"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyEffort("high") == .replaceDraft(""))
    #expect(await defaults.thinkingCalls == ["high"])

    await defaults.setShouldFail(true)
    #expect(model.updateDraft("/model"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyModel(first) == .none)
    #expect(model.route == .native(.model))
    #expect(model.inlineMessage == "Couldn’t update the default model.")
    await defaults.setShouldFail(false)
    #expect(await model.applyModel(first) == .replaceDraft(""))
}

@MainActor
@Test func commandModelDelegatesActiveNativeModelEffortAndFastExactlyOnce() async {
    let first = commandModelInfo(id: "one")
    let second = commandModelInfo(id: "two")
    let catalog = ControlsCommandCatalog(models: [first, second], selected: first)
    let controls = ComposerControlsModel(catalog: catalog, defaults: RecordingCommandDefaults())
    await controls.refresh(authenticatedProviderIDs: ["test"], projectURL: nil)
    let session = NativeCommandSession(catalog: .available(commandModelCommands))
    controls.attachActiveSession(session)
    let model = ComposerCommandModel(catalog: catalog, controls: controls) { _, _ in }
    model.attachActiveSession(session)

    #expect(model.updateDraft("/model"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyModel(second) == .replaceDraft(""))
    #expect(session.modelCalls.count == 1)
    #expect(session.modelCalls.first?.0 == "test")
    #expect(session.modelCalls.first?.1 == "two")
    #expect(model.updateDraft("/effort"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyEffort("high") == .replaceDraft(""))
    #expect(session.thinkingCalls == ["high"])
    #expect(model.updateDraft("/fast"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyFast(true) == .replaceDraft(""))
    #expect(session.fastCalls == [true])
}

@MainActor
@Test func commandModelKeepsNativeModelOpenWhenControlsHaveNoActiveController() async {
    let first = commandModelInfo(id: "one")
    let second = commandModelInfo(id: "two")
    let catalog = ControlsCommandCatalog(models: [first, second], selected: first)
    let controls = ComposerControlsModel(catalog: catalog, defaults: RecordingCommandDefaults())
    await controls.refresh(authenticatedProviderIDs: ["test"], projectURL: nil)
    let model = ComposerCommandModel(catalog: catalog, controls: controls) { _, _ in }
    let commandSession = CommandModelSession(state: .idle, catalog: .available(commandModelCommands))
    model.attachActiveSession(commandSession)

    #expect(model.updateDraft("/model"))
    #expect(await model.activate() == .keepDraft)
    #expect(await model.applyModel(second) == .none)
    #expect(model.route == .native(.model))
    #expect(model.isPresented)
    #expect(model.inlineMessage == "Couldn’t update this setting.")
}

@MainActor
@Test func commandModelKeepsNativeModelOpenForRepeatedIdenticalFailures() async {
    let first = commandModelInfo(id: "one")
    let second = commandModelInfo(id: "two")
    let catalog = ControlsCommandCatalog(models: [first, second], selected: first)
    let defaults = RecordingCommandDefaults()
    await defaults.setShouldFail(true)
    let controls = ComposerControlsModel(catalog: catalog, defaults: defaults)
    await controls.refresh(authenticatedProviderIDs: ["test"], projectURL: nil)
    let model = ComposerCommandModel(catalog: catalog, controls: controls) { _, _ in }

    #expect(model.updateDraft("/model"))
    #expect(await model.activate() == .keepDraft)
    for _ in 0..<100 {
        #expect(await model.applyModel(second) == .none)
        #expect(model.route == .native(.model))
    }
    #expect(await defaults.modelCalls.count == 100)
    #expect(model.inlineMessage == "Couldn’t update the default model.")
}

@MainActor
@Test func commandModelSwitchesGenerationsAndIgnoresStaleStreams() async {
    let warmSkill = AvailableSlashCommand(name: "skill:warm", source: .skill)
    let warmPrompt = AvailableSlashCommand(name: "prompt:warm", source: .mcpPrompt)
    let sessionCommand = AvailableSlashCommand(name: "session", source: .builtin)
    let sessionExtension = AvailableSlashCommand(name: "extension:session", source: .extensionCommand)
    let catalog = StreamingCommandCatalog(initial: .available([warmSkill]))
    let model = commandModel(catalog: catalog)
    #expect(await eventually { model.updateDraft("/") && model.visibleRows.contains { $0.canonicalName == "skill:warm" } })

    let first = StreamingCommandSession(state: .idle, catalog: .available([sessionCommand]))
    model.attachActiveSession(first)
    #expect(model.updateDraft("/"))
    #expect(model.visibleRows.contains { $0.canonicalName == "session" })
    await catalog.yield(.available([warmPrompt]))
    first.yield(.available([sessionExtension]))
    #expect(await eventually { model.visibleRows.contains { $0.canonicalName == "extension:session" } })
    #expect(!model.visibleRows.contains { $0.canonicalName == "prompt:warm" })

    model.detachActiveSession()
    first.yield(.available([sessionCommand]))
    #expect(await eventually { model.visibleRows.contains { $0.canonicalName == "prompt:warm" } })
    #expect(!model.visibleRows.contains { $0.canonicalName == "session" })

    for _ in 0..<100 {
        let replacement = StreamingCommandSession(state: .idle, catalog: .available([sessionCommand]))
        model.attachActiveSession(replacement)
        model.detachActiveSession()
        replacement.yield(.available([sessionExtension]))
    }
    await catalog.yield(.available([warmSkill]))
    #expect(await eventually { model.visibleRows.contains { $0.canonicalName == "skill:warm" } })
}

@MainActor
@Test func commandModelResetsInvalidDraftAndRetainsSelectionAcrossMultilineArguments() async {
    let commands = [AvailableSlashCommand(name: "compact", inputHint: "[note]", source: .builtin)]
    let session = CommandModelSession(state: .idle, catalog: .available(commands))
    let model = commandModel(catalog: CommandModelCatalog(commands: commands))
    model.attachActiveSession(session)
    #expect(model.updateDraft("/compact first\nsecond"))
    let compact = CommandBrowserRowID(rawSource: "builtin", canonicalName: "compact")
    #expect(model.selectedRowID == compact)
    #expect(model.updateDraft("/compact replacement\nbody"))
    #expect(model.selectedRowID == compact)
    #expect(model.complete() == .replaceDraft("/compact replacement\nbody"))
    #expect(model.updateDraft("plain text") == false)
    #expect(!model.isPresented)
    #expect(model.selectedRowID == nil)
    #expect(model.route == .root)
    #expect(model.inlineMessage == nil)
}

private let commandModelCommands = [
    AvailableSlashCommand(name: "compact", aliases: ["alias"], inputHint: "[note]", source: .builtin),
    AvailableSlashCommand(name: "skill:write", source: .skill),
]

private func keyDown(
    keyCode: UInt16,
    characters: String = "",
    modifiers: NSEvent.ModifierFlags = []
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 1,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode)!
}

@MainActor
private func commandModel(catalog: any ComposerCatalogLoading) -> ComposerCommandModel {
    ComposerCommandModel(catalog: catalog, controls: ComposerControlsModel(catalog: catalog, defaults: CommandModelDefaults())) { _, _ in }
}

private actor CommandModelCatalog: ComposerCatalogLoading {
    nonisolated let commandUpdates: AsyncStream<ComposerCommandCatalogState>

    init(commands: [AvailableSlashCommand] = commandModelCommands) {
        let updates = AsyncStream<ComposerCommandCatalogState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        commandUpdates = updates.stream
        updates.continuation.yield(.available(commands))
        updates.continuation.finish()
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        ComposerCatalogSnapshot(
            models: [], selected: nil, thinkingLevel: nil,
            fastModeEnabled: false, fastModeActive: false)
    }

    func shutdown() async {}
}

private actor StreamingCommandCatalog: ComposerCatalogLoading {
    nonisolated let commandUpdates: AsyncStream<ComposerCommandCatalogState>
    private let continuation: AsyncStream<ComposerCommandCatalogState>.Continuation

    init(initial: ComposerCommandCatalogState) {
        let updates = AsyncStream<ComposerCommandCatalogState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        commandUpdates = updates.stream
        continuation = updates.continuation
        continuation.yield(initial)
    }

    func yield(_ state: ComposerCommandCatalogState) {
        continuation.yield(state)
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot {
        ComposerCatalogSnapshot(models: [], selected: nil, thinkingLevel: nil, fastModeEnabled: false, fastModeActive: false)
    }

    func shutdown() async {}
}

@MainActor
private final class CommandModelSession: ComposerCommandSession {
    var runtimeState: SessionRuntimeState
    var commandCatalogState: ComposerCommandCatalogState
    let commandUpdates = AsyncStream<ComposerCommandCatalogState> { _ in }
    private(set) var sent: [String] = []

    init(state: SessionRuntimeState, catalog: ComposerCommandCatalogState) {
        runtimeState = state
        commandCatalogState = catalog
    }

    func sendSlashCommand(_ text: String) async { sent.append(text) }
}

@MainActor
private final class StreamingCommandSession: ComposerCommandSession {
    var runtimeState: SessionRuntimeState
    var commandCatalogState: ComposerCommandCatalogState
    let commandUpdates: AsyncStream<ComposerCommandCatalogState>
    private let continuation: AsyncStream<ComposerCommandCatalogState>.Continuation
    private(set) var sent: [String] = []

    init(state: SessionRuntimeState, catalog: ComposerCommandCatalogState) {
        runtimeState = state
        commandCatalogState = catalog
        let updates = AsyncStream<ComposerCommandCatalogState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        commandUpdates = updates.stream
        continuation = updates.continuation
    }

    func yield(_ state: ComposerCommandCatalogState) {
        commandCatalogState = state
        continuation.yield(state)
    }

    func sendSlashCommand(_ text: String) async { sent.append(text) }
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<256 {
        if condition() { return true }
        await Task.yield()
    }
    return false
}

private actor CommandModelDefaults: ComposerDefaultPersisting {
    func setDefaultModel(provider: String, modelID: String) async throws {}
    func setDefaultThinkingLevel(_ level: String) async throws {}
}

private actor RecordingCommandDefaults: ComposerDefaultPersisting {
    private(set) var modelCalls: [(String, String)] = []
    private(set) var thinkingCalls: [String] = []
    private var shouldFail = false

    func setShouldFail(_ value: Bool) { shouldFail = value }

    func setDefaultModel(provider: String, modelID: String) async throws {
        modelCalls.append((provider, modelID))
        if shouldFail { throw CommandModelError.failed }
    }

    func setDefaultThinkingLevel(_ level: String) async throws {
        thinkingCalls.append(level)
        if shouldFail { throw CommandModelError.failed }
    }
}

private actor ControlsCommandCatalog: ComposerCatalogLoading {
    private let snapshot: ComposerCatalogSnapshot
    nonisolated let commandUpdates = AsyncStream<ComposerCommandCatalogState>(
        bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(.available(commandModelCommands))
            continuation.finish()
        }

    init(models: [ComposerModelInfo], selected: ComposerModelInfo) {
        snapshot = ComposerCatalogSnapshot(
            models: models,
            selected: selected,
            thinkingLevel: "auto",
            fastModeEnabled: false,
            fastModeActive: false)
    }

    func load(projectURL: URL?) async throws -> ComposerCatalogSnapshot { snapshot }
    func shutdown() async {}
}

@MainActor
private final class NativeCommandSession: ComposerCommandSession, ComposerSessionControlling {
    var runtimeState: SessionRuntimeState = .idle
    var commandCatalogState: ComposerCommandCatalogState
    let commandUpdates = AsyncStream<ComposerCommandCatalogState> { _ in }
    var liveComposerSelection = ComposerLiveSelection(
        provider: "test", modelID: "one", thinkingLevel: "auto", fastModeEnabled: false)
    private(set) var sent: [String] = []
    private(set) var modelCalls: [(String, String)] = []
    private(set) var thinkingCalls: [String] = []
    private(set) var fastCalls: [Bool] = []

    init(catalog: ComposerCommandCatalogState) { commandCatalogState = catalog }

    func sendSlashCommand(_ text: String) async { sent.append(text) }
    func setModel(provider: String, modelID: String) async throws { modelCalls.append((provider, modelID)) }
    func setThinkingLevel(_ level: String) async throws { thinkingCalls.append(level) }
    func setFastMode(_ enabled: Bool) async throws -> Bool {
        fastCalls.append(enabled)
        return true
    }
}

private enum CommandModelError: Error { case failed }

private func commandModelInfo(id: String) -> ComposerModelInfo {
    ComposerModelInfo(
        modelID: id,
        name: id,
        provider: "test",
        api: "anthropic-messages",
        thinkingEfforts: ["auto", "high"],
        requiresEffort: false)
}
