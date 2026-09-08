# Skill Completion Dismissal

**Status:** Approved

**Date:** 2026-09-01

**Platform:** macOS 15+, Swift 6.1, SwiftUI

## Goal

Accepting a highlighted skill from the composer command browser completes the
canonical skill token without sending it. Tab, Enter, and the equivalent row
click close the browser and leave the completed skill in the editor so the user
can add instructions or send it deliberately with a later Enter.

## Root cause

`ComposerCommandModel.needsArgumentStage(_:)` currently treats every skill as
requiring the browser's argument route. Tab therefore writes the canonical skill
plus a trailing space but deliberately keeps the browser presented. Enter in
that route executes the staged skill, which makes an attempt to finish completion
submit the message instead.

The argument route adds no skill-specific input control; freeform instructions
are still typed in the composer. Keeping the browser open does not help with
that input and makes the completion state ambiguous.

## Approved behavior

For a highlighted skill with no subcommands:

1. Tab or Enter replaces the typed alias/query with the canonical slash token.
2. The completed draft retains a trailing space for optional instructions.
3. The command browser dismisses.
4. No session starts and no slash command is sent.
5. Editor focus remains in the composer after the completed token.
6. A later Enter, after the browser has closed, uses the normal send path.

Single-clicking the highlighted skill follows the same activation transition as
Enter and therefore also completes without sending. A skill that advertises
subcommands keeps the existing subcommand selection route before completion.

## Scope boundaries

- Implement the behavior in `ComposerCommandModel`, which owns command routing
  and effects. Do not add skill-specific keyboard rules to `ComposerView`.
- Preserve aliases, canonicalization, existing draft suffixes, attachments, and
  active/new-session distinctions.
- Preserve existing behavior for App controls, ordinary OMP commands,
  extensions, and prompt workflows.
- Update the skill detail metadata so its Enter and Tab hints describe
  completion rather than opening or execution.
- Do not change command discovery, filtering, ranking, layout, or animation.

## State transition

```text
root browser + highlighted skill
  -- Tab / Enter / row click --> canonical skill draft + trailing space
                               browser dismissed
                               editor focused
                               nothing sent

composer with completed skill
  -- later Enter ------------> existing send path
```

## Testing

- Add model regression coverage proving Tab completion returns the canonical
  draft, dismisses presentation, and sends nothing.
- Add activation coverage proving Enter produces the same non-sending result.
- Cover both a new-session composer and an active session.
- Preserve a subcommand-bearing skill's child route.
- Update presentation assertions for the skill keyboard hints.
- Run the focused command-model tests, the full test suite, and a clean Release
  build.
- In the packaged app, invoke `/skill:using-superpowers` through a partial query
  and verify Tab and Enter each close the browser without sending. Confirm a
  subsequent Enter sends normally.

## Non-goals

- Changing how non-skill commands execute.
- Removing freeform arguments from skills.
- Changing prompt workflow completion.
- Adding a new editor or completion component.
