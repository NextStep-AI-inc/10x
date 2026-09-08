# Task cards and file-reference accuracy

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix audit B06 empty task cards and B07 code expressions exposed as file links.

**Architecture:** Correct shared content extraction rather than patching rendered cards. Preserve legacy payload support.

**Tech Stack:** Swift, OmpKit JSONValue, Swift Testing.

- [ ] Add regression checks in `ToolContentExtractorTests.swift` for actual OMP 18 `details.phases[].tasks[]` results, authoritative empty snapshots and pre-result `list[].items[]` initialization. Include phase/blocker context and completed counts. The installed contract is `@oh-my-pi/pi-coding-agent/src/tools/todo.ts`, `TodoToolDetails` and `todoSchema`.
- [ ] Add tests in `TranscriptReferenceTests.swift`: `args.output.write_text(payload)` and `sys.stdout.write(payload)` are not links, while `Sources/Foo (copy).swift` remains valid.
- [ ] Run those exact functions before production changes and confirm assertion failures.
- [ ] In `App/Tools/ToolContentExtractor.swift`, introduce one shared `todoValues(arguments:result:)` extraction for both `todos` and `todoCard`. Prefer confirmed result phases, flatten tasks in phase order and retain phase/blocker as detail; preserve flat legacy todos and derive pending initialization rows from actual list/items input only when no result exists. Empty result phases must not fall back to obsolete arguments.
- [ ] In `App/Sessions/TranscriptReference.swift`, require a plausible relative-file extension consisting of letters/numbers/underscore/hyphen, with at least one letter. This rejects function-call suffixes without banning parentheses in legitimate filename stems. Absolute and explicit relative path behavior stays intact.
- [ ] Run the regressions plus existing tool/reference tests, inspect actual nonzero execution, then verify task cards and inline code in Release UI. Commit only owned files and evidence.
