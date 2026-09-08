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

## Task 2: Current running command output

Status: complete

- Threads the tool phase through direct and nested tool surfaces.
- Running consoles use a bounded reverse scan to keep the newest ten lines visible; Show more extends backward while keeping the newest line.
- Completed consoles retain the existing head-first presentation and Copy retains the full payload received by the app.
- Red evidence: `/tmp/10x-tool-details-task2-red.log` failed because the bounded window API did not exist.
- Focused verification: `/tmp/10x-tool-details-task2-focused.log`, 5 tests passed, 0 failures. This covered the 40-to-41-line tail update, backward reveal, complete head mode, finite 10,000-line and 100,000-character ceilings, streaming extraction, and reducer replacement.
- No snapshot candidate was created. Live Show more and Copy interaction remain for parent Release QA.
