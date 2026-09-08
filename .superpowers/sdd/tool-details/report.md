# Tool details implementation report

Base: `4ed296b`

## Task 1: Accurate, advancing tool durations

Status: complete

- Pre-indexes exact persisted `custom` / `tool_execution_start` markers and uses their finite ISO-8601 `startedAt` values.
- Marks historical tools without an exact marker as having no reliable start, omitting their duration and excluding their fallback start from turn bounds.
- Keeps live event starts reliable and exposes deterministic `durationLabel(at:)` calculation with negative clamping.
- Updates only a running tool's status area once per second; settled tool cards remain static.
- Red evidence: `/tmp/10x-tool-details-task1-red.log` failed because the old duration was a non-callable wall-clock-backed string.
- Focused verification: `/tmp/10x-tool-details-task1-focused.log`, 35 tests passed, 0 failures. This covered all top-level tests in `TranscriptHistoryMapperTests.swift`, `TranscriptTurnProjectionTests.swift`, and `ToolDisclosureStateTests.swift`.
- No snapshot candidate was created. Native timer behavior remains for parent Release QA.
