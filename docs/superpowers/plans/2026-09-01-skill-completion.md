# Skill Completion Dismissal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Tab, Enter, and row activation complete a highlighted skill into the composer and close the command browser without sending it.

**Architecture:** Keep the behavior in `ComposerCommandModel`, the existing owner of command routes and effects. A single helper canonicalizes an argument-capable skill, dismisses model presentation, and returns the existing `replaceDraft` effect; both completion and activation call it after preserving subcommand routing. `CommandBrowserView` only updates its per-row keyboard hints to describe the model behavior.

**Tech Stack:** Swift 6.1, SwiftUI, Swift Testing, XCTest/xcodebuild, macOS 15+

---

## File map

- Modify `Tests/TenXAppTests/ComposerCommandModelTests.swift`: replace the old skill-argument-stage expectations with regression coverage for Tab, Enter, new sessions, active sessions, generic OMP input hints, and skill subcommands.
- Modify `App/Sessions/ComposerCommandModel.swift`: route argumentless skill completion and activation through one non-sending dismissal helper.
- Modify `App/Sessions/CommandBrowserView.swift`: make the Enter and Tab detail hints say that skills complete in the prompt.
- Do not modify `10x.xcodeproj`; no files are added under `App/` or `Tests/`.

### Task 1: Lock the corrected skill state transition with failing tests

**Files:**
- Modify: `Tests/TenXAppTests/ComposerCommandModelTests.swift:266-283`
- Modify: `Tests/TenXAppTests/ComposerCommandModelTests.swift:340-434`
- Modify: `Tests/TenXAppTests/ComposerCommandModelTests.swift:721-741`
- Test: `Tests/TenXAppTests/ComposerCommandModelTests.swift`

- [ ] **Step 1: Replace the new-session execution expectation with non-sending completion**

Change `commandModelAllowsOnlySkillsForNewSessions` so the first Enter accepts the skill, closes presentation, and leaves session creation untouched:

```swift
#expect(await model.activate() == .replaceDraft("/skill:write "))
#expect(!model.isPresented)
#expect(model.route == .root)
#expect(started.isEmpty)
```

Keep the existing `/compact` assertion to prove an unavailable new-session command still cannot execute.

- [ ] **Step 2: Add one active-session regression test covering both keyboard actions and real skill metadata**

Add this test beside `commandModelCompletesCanonicalCommandsWithoutSending`:

```swift
@MainActor
@Test func commandModelCompletesSkillsWithTabOrEnterWithoutSending() async {
    let skill = AvailableSlashCommand(
        name: "skill:using-superpowers",
        inputHint: "arguments",
        source: .skill)
    let session = CommandModelSession(state: .idle, catalog: .available([skill]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [skill]))
    model.attachActiveSession(session)
    let rowID = CommandBrowserRowID(
        rawSource: "skill",
        canonicalName: "skill:using-superpowers")

    #expect(model.updateDraft("/using-superpowers"))
    model.highlight(rowID)
    #expect(model.complete() == .replaceDraft("/skill:using-superpowers "))
    #expect(!model.isPresented)
    #expect(model.route == .root)
    #expect(session.sent.isEmpty)

    #expect(model.updateDraft("/using-superpowers keep context"))
    model.highlight(rowID)
    #expect(await model.activate() == .replaceDraft("/skill:using-superpowers keep context"))
    #expect(!model.isPresented)
    #expect(model.route == .root)
    #expect(session.sent.isEmpty)
}
```

The `inputHint: "arguments"` fixture is intentional: current OMP metadata advertises this generic hint for the reported skill, but completion must still dismiss because freeform input remains in the composer.

- [ ] **Step 3: Preserve skill subcommand routing**

Add a focused test proving the new skill branch does not skip a real child selector:

```swift
@MainActor
@Test func commandModelKeepsSubcommandBearingSkillsInTheChildRoute() async {
    let skill = AvailableSlashCommand(
        name: "skill:parent",
        subcommands: [AvailableSlashSubcommand(name: "child")],
        source: .skill)
    let session = CommandModelSession(state: .idle, catalog: .available([skill]))
    let model = commandModel(catalog: CommandModelCatalog(commands: [skill]))
    model.attachActiveSession(session)

    #expect(model.updateDraft("/parent"))
    #expect(await model.activate() == .replaceDraft("/skill:parent "))
    #expect(model.route == .subcommands(CommandBrowserRowID(
        rawSource: "skill",
        canonicalName: "skill:parent")))
    #expect(session.sent.isEmpty)
}
```

- [ ] **Step 4: Update tests whose old premise was “all skills enter argument mode”**

Make these exact scope changes:

- In `commandModelCompletesCanonicalCommandsWithoutSending`, expect skill completion to set `isPresented == false` and `route == .root`; keep the prompt workflow expectation in `.arguments`.
- Rename `commandModelKeepsStagedSkillAndPromptArgumentsWhenComposerObserverSeesEdits` to `commandModelKeepsStagedPromptArgumentsWhenComposerObserverSeesEdits` and run only the `.mcpPrompt` fixture.
- In `commandModelReturnsToRootWhenComposerObserverSeesAChangedStagedCommand`, stage `/compact` first, then change the draft to `/skill:write` and assert the route returns to `.root` with the skill highlighted.
- In `commandModelStartsOnlySkillsAndPromptsForNewSessionsWithAttachments`, keep the two-stage execution assertion only for `prompt:review`; assert skill activation completes and leaves `starts` empty before exercising the prompt.

Use these final expectations for the new-session attachment distinction:

```swift
#expect(model.updateDraft("/skill:write"))
model.highlight(CommandBrowserRowID(rawSource: "skill", canonicalName: "skill:write"))
#expect(await model.activate(attachments: [attachment]) == .replaceDraft("/skill:write "))
#expect(starts.isEmpty)

#expect(model.updateDraft("/prompt:review"))
model.highlight(CommandBrowserRowID(rawSource: "mcp_prompt", canonicalName: "prompt:review"))
#expect(await model.activate(attachments: [attachment]) == .replaceDraft("/prompt:review "))
#expect(await model.activate(attachments: [attachment]) == .executed)
#expect(starts.map(\.0) == ["/prompt:review "])
#expect(starts.first?.1.map(\.id) == [attachment.id])
```

- [ ] **Step 5: Run the focused tests and verify the new regression fails for the right reason**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test \
  -only-testing:TenXAppTests/commandModelCompletesSkillsWithTabOrEnterWithoutSending
```

Expected: FAIL because the first completion leaves `isPresented` true and `.arguments`, while activation follows the same old argument-stage behavior.

### Task 2: Implement the shared non-sending skill completion

**Files:**
- Modify: `App/Sessions/ComposerCommandModel.swift:220-244`
- Modify: `App/Sessions/ComposerCommandModel.swift:270-302`
- Modify: `App/Sessions/ComposerCommandModel.swift:532-550`
- Test: `Tests/TenXAppTests/ComposerCommandModelTests.swift`

- [ ] **Step 1: Route Tab completion through a skill-specific shared helper**

At the start of the `.omp` branch in `complete()`, before `requiresStage`, add:

```swift
if row.source == .skills, row.subcommands.isEmpty {
    return completeSkill(row)
}
```

- [ ] **Step 2: Route Enter and row activation through the same helper**

In the `.omp` branch of `activate(attachments:)`, keep the existing non-empty subcommand block first. Immediately after it, add:

```swift
if row.source == .skills, row.subcommands.isEmpty {
    return completeSkill(row)
}
```

This ordering preserves child selection for a skill that advertises subcommands. The row click already calls `activate`, so it receives the same behavior without view-specific logic.

- [ ] **Step 3: Add the minimal helper next to `needsArgumentStage(_:)`**

```swift
private func completeSkill(_ row: CommandBrowserRow) -> CommandBrowserEffect {
    let canonical = canonicalSlashText(for: row, trailingSpace: true)
    dismissPresentation()
    return .replaceDraft(canonical)
}
```

Do not remove `.skills` from `needsArgumentStage(_:)`; the new branch is intentionally narrower and keeps the old fallback semantics for any non-root path.

- [ ] **Step 4: Run the focused command-model regression**

Run the Task 1 command again.

Expected: PASS, including canonical `/skill:using-superpowers ` output, dismissed presentation, root route, and zero sent commands.

- [ ] **Step 5: Run every command-model test**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test \
  -only-testing:TenXAppTests/ComposerCommandModelTests
```

Expected: all selected command-model tests PASS. If Xcode selects zero tests for the file-level filter, run the full `TenXAppTests` target instead and record the actual count.

- [ ] **Step 6: Commit the model fix and regression coverage**

```bash
git add App/Sessions/ComposerCommandModel.swift Tests/TenXAppTests/ComposerCommandModelTests.swift
git commit -m "fix(composer): complete skills without sending"
git push
```

### Task 3: Make the browser hints match the corrected interaction

**Files:**
- Modify: `App/Sessions/CommandBrowserView.swift:299-313`
- Test: packaged Release app

- [ ] **Step 1: Update only the skill row's Enter and Tab descriptions**

Before editing user-facing copy, read the `writing-ui` and `visual-ui` skills.

Replace the two action-hint branches in `detailMetadata(for:)` with:

```swift
if row.source == .skills, row.subcommands.isEmpty {
    detailPair("Enter", "Complete in prompt")
} else if let executionNote = row.executionNote {
    detailPair("Enter", executionNote)
} else {
    detailPair("Enter", row.source == .app ? "Open control" : "Open")
}
detailPair(
    "Tab",
    (row.source == .skills && row.subcommands.isEmpty)
        || (row.inputHint == nil && row.subcommands.isEmpty)
        ? "Complete in prompt"
        : "Complete with input")
```

Do not change the global header hint; `↵ open` remains accurate for the browser generally, while the detail pane describes the selected skill's specialized action.

- [ ] **Step 2: Build the app after the copy change**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` with no new compiler errors.

- [ ] **Step 3: Commit the hint correction**

```bash
git add App/Sessions/CommandBrowserView.swift
git commit -m "fix(composer): clarify skill completion hints"
git push
```

### Task 4: Verify the branch and hand off the packaged build

**Files:**
- Verify: `App/Sessions/ComposerCommandModel.swift`
- Verify: `App/Sessions/CommandBrowserView.swift`
- Verify: `Tests/TenXAppTests/ComposerCommandModelTests.swift`

- [ ] **Step 1: Confirm the branch contains only the approved scope**

Before making completion claims or launching the build, read the
`verifying-work` and `launching-local-builds` skills. Use the `computer-use`
skill for packaged-app interaction.

Run:

```bash
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
git status --short --branch
```

Expected: no whitespace errors; only the spec, plan, two composer source files, and composer model tests differ; worktree is clean.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Expected: all 1,097+ tests PASS. The pre-change baseline produced timing failures in three unrelated session-lifecycle tests; a red repeat must be reported and independently reproduced, not silently attributed to this composer change.

- [ ] **Step 3: Produce a clean Release build**

Run:

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /private/tmp/tenx-skill-completion-release clean build
codesign --force --deep --sign - \
  /private/tmp/tenx-skill-completion-release/Build/Products/Release/10x.app
```

Expected: `** BUILD SUCCEEDED **`, followed by a successful ad-hoc signature.

- [ ] **Step 4: Verify both completion keys in the real packaged app**

Launch the exact Release app and confirm its window is visible. In a new-session composer:

1. Type `/using-superpowers`, highlight `/skill:using-superpowers`, and press Tab.
2. Verify the draft becomes `/skill:using-superpowers `, the browser closes, editor focus remains, and no transcript turn/session starts.
3. Clear the draft, repeat the partial query, and press Enter.
4. Verify the same completed draft and non-sending dismissal.
5. Capture a screenshot showing the completed skill in the composer with the browser closed.

Do not press the subsequent Enter through automation; that would send a real provider request. Leave the packaged app open for Tanner to confirm the unchanged final-send behavior.

- [ ] **Step 5: Update the draft PR and report the auth blocker if it remains**

Update the PR body with exact test counts, Release build evidence, manual verification, screenshot path, and the two implementation commits. If `gh` still returns HTTP 401, report the pushed branch and the PR creation URL instead of claiming a PR exists.

Do not merge or push directly to `main` without explicit authorization.
