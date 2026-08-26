# Persistent Session Search Design

**Date:** 2026-08-25
**Status:** Approved architecture
**Scope:** Local session search indexing, query coordination, and search performance verification

## Problem

The Release app is idle-efficient, but search reparses the complete local session corpus after every query mutation. The profiled corpus contains 51 JSONL files totaling 21.7 MB. One full-corpus miss takes approximately 1.0 second and temporarily grows RSS by approximately 16 MB. Entering a 22-character query drives the app to approximately 30–50% CPU and a 157.5 MB peak physical footprint.

The Time Profiler sample attributes 1.299 CPU-seconds to `SessionSearchService.search`, including 1.128 CPU-seconds in `SessionFileParser.parse`. `SearchModalModel` starts work immediately on each keystroke. Cancellation is only checked between entries, so it cannot interrupt a large file decode already in progress.

## Goals

- Query unchanged session history without reopening or decoding its JSONL source.
- Keep indexed content current across file additions, removals, and `(modification date, size)` changes.
- Preserve session, message, tool, path, case-insensitive, diacritic-insensitive, and arbitrary-substring matches.
- Keep idle startup free of indexing CPU.
- Bound first-time indexing memory to one parsed session.
- Preserve the current result shape, 200-result cap, filters, selection, and progress indicator.
- Add deterministic regression coverage and repeatable Release profiling instructions.

## Non-goals

- Changing the search modal layout or user-facing copy.
- Indexing subagent transcript files that `SessionLibrary` does not list.
- Replacing `SessionFileParser` or changing the JSONL source format.
- Adding a third-party search or database dependency.

## Architecture

```text
SearchModalModel
  │ 250 ms debounce
  ▼
SessionSearchService actor
  ├── compare SessionMetadata with indexed_session
  ├── parse each changed JSONL file once
  ├── atomically replace that session's documents
  └── query SQLite FTS5
                 │
                 ▼
          [SearchResult], max 200
```

`AppDependencies` owns one shared `SessionSearchService`. `AppModel` passes it to each `SearchModalView`, so modal recreation does not recreate the database connection or synchronization state. Opening search refreshes `AppModel.sessions`; the query path synchronizes the supplied metadata before searching.

## Storage

The app uses the system `SQLite3` library and FTS5. The database lives in Application Support under `10x/SearchIndex-v1.sqlite`. Its directory is owner-only, the database is owner read/write, and the database is excluded from backups because it is derived from local files.

The connection enables WAL journaling, `synchronous=NORMAL`, and schema version `1`:

```sql
CREATE TABLE indexed_session (
    path TEXT PRIMARY KEY NOT NULL,
    modified REAL NOT NULL,
    size_bytes INTEGER NOT NULL
);

CREATE VIRTUAL TABLE search_document USING fts5(
    session_path UNINDEXED,
    entry_id UNINDEXED,
    project_path UNINDEXED,
    title UNINDEXED,
    excerpt UNINDEXED,
    result_kind UNINDEXED,
    session_modified UNINDEXED,
    entry_order UNINDEXED,
    normalized_text,
    tokenize = 'trigram remove_diacritics 1'
);
```

Each session contributes one session document followed by one document for every searchable message or tool entry. Result metadata lives beside the indexed text, so a query never reopens the JSONL file. `session_modified` and `entry_order` preserve newest-session-first and file-order result ordering.

Text and queries are folded with a fixed POSIX locale using case- and diacritic-insensitive normalization. Queries of at least three characters use a parameter-bound, quoted trigram `MATCH`. One- and two-character queries use parameter-bound `instr(normalized_text, ?)` against the persistent table. Query text is never interpolated into SQL.

## Synchronization

`SessionSearchService` remains an actor and owns a focused `SessionSearchDatabase` value. Before querying, it synchronizes the current `SessionMetadata` snapshot:

1. Remove rows for sessions no longer present.
2. Reuse rows whose path, modification date, and byte size match.
3. Parse one new or changed file outside a write transaction.
4. Recheck modification date and size after parsing. If either changed, retain the prior valid rows and retry during the next synchronization.
5. Replace that session's documents and metadata in one transaction.

Cancellation is checked between sessions and entries. A parse failure retains the last valid rows. Deletion removes rows. Processing one changed file at a time bounds transient memory to one `ParsedSessionFile` rather than the complete corpus.

The index is lazy. Opening search refreshes session metadata, but no file is parsed until a query arrives. The first search after installation may build the index once; subsequent launches only parse changed sessions. This avoids moving the original CPU spike to app startup.

## Query Coordination

`SearchModalModel` waits 250 ms after the latest non-empty query mutation. Changing or clearing the query cancels the pending delay. Results are installed only when the task remains current. The existing progress indicator covers synchronization and querying, so no visual or text change is required.

The service returns `SearchResult` values ordered by session modification date and entry order. Session documents precede entries from the same file, matching current behavior.

## Failure Handling

- SQLite operations throw typed `SessionSearchDatabaseError` values containing the operation and sanitized database message.
- A schema mismatch or corrupt index closes and removes only the derived database and its WAL sidecars, then rebuilds once.
- A second database failure is logged with the format `[SearchIndex:<operation>] Search index unavailable — {message}` and returns an empty result without terminating the app.
- Session source files are never modified by database creation, reset, or synchronization.
- A source file that changes during parsing keeps its prior valid index rows.

## Verification

Deterministic tests cover:

- Session, message, tool argument, path, case, diacritic, and substring matches.
- Safe handling of quotes, punctuation, one-character, and two-character queries.
- No source-file parse for repeated queries against unchanged metadata.
- Atomic replacement after modification date or size changes.
- Removal of deleted sessions.
- Corrupt database recovery from source fixtures.
- Only the final search dispatch after rapid query changes.

The original Release workload will be repeated against the same 51-file, 21.7 MB corpus. Acceptance thresholds on the profiling machine are:

- Idle remains at or below 1% CPU before and after a search.
- A warm full-corpus search returns in at most 100 ms.
- Entering the same 22-character query dispatches one search, peaks below 15% app CPU, and remains below 125 MB physical footprint.
- The Time Profiler trace contains no `SessionFileParser.parse` work for a warm query.
- Existing app tests, OmpKit tests, and the Release build pass.

RSS and physical footprint are recorded separately because they are different operating-system memory measures. Binary Instruments traces remain local; the repository records the commands, corpus dimensions, environment, and before/after metrics.

## Rollout

The database is a disposable cache and needs no source-data migration. A schema-version change resets and rebuilds it. Removing the app-owned index never removes or edits OMP sessions.
