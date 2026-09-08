# Persistent Session Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace per-keystroke JSONL corpus parsing with one shared, lazy, incrementally synchronized SQLite FTS5 index, then prove the warm search workload meets the approved CPU, memory, and latency limits.

**Architecture:** AppDependencies owns a single SessionSearchService actor. On a non-empty debounced query, the actor compares supplied session metadata with persistent fingerprints, parses only new or changed files, replaces each changed session atomically, and queries stored result metadata. SearchModalModel waits 250 ms and publishes only the current request.

**Tech Stack:** macOS 15+, Swift 6, SwiftUI Observation, Foundation, system SQLite3/FTS5, Swift Testing, xcodebuild, Instruments. No third-party dependency.

**Spec:** docs/superpowers/specs/2026-08-25-persistent-session-search-design.md

**Measured baseline:** Release build, 51 session files, 21.7 MB total. One miss is about 1.0 s with about 16 MB transient RSS. A 22-prefix typing run takes about 6.2 s, reaches 30–50% app CPU and 157.5 MB peak physical footprint, and records 1.128 CPU-s in SessionFileParser.parse. Settled idle is about 0% CPU and 91 MB RSS.

## Constraints

- Work only in codex/performance-runoff at /Users/tannerpham/CS Projects/.worktrees/10x-performance-profile.
- When both approved plans are executed, complete Transcript Event Pipeline Task 1 first so the controlled transcript baseline is captured before any app implementation changes.
- Load schema-changes before editing the SQLite schema or generated project linkage, then use test-driven-development for each behavioral task.
- Keep the current SearchResult shape, 200-result limit, ordering, filters, selection, progress state, layout, and user-facing copy.
- Search source files are read-only. Reset may delete only SearchIndex-v1.sqlite and its WAL/SHM sidecars.
- Use a fixed en_US_POSIX locale for normalization and bind every query value.
- Run ruby scripts/generate_xcodeproj.rb after adding Swift files or changing project linkage.
- Verify a Release build, not a dev build. Load launching-local-builds before launching it and verifying-work before claiming completion.
- A draft PR cannot be opened because this repository has no remote; atomic commits are the handoff boundary.

## Task 1: Build and test the SQLite FTS boundary

**Files:**
- Create: App/Search/SessionSearchDatabase.swift
- Create: App/Search/SessionSearchDocument.swift
- Create: Tests/TenXAppTests/SessionSearchDatabaseTests.swift
- Modify: scripts/generate_xcodeproj.rb
- Regenerate: 10x.xcodeproj/project.pbxproj

- [ ] Add the system SQLite library to scripts/generate_xcodeproj.rb immediately after OmpKit product linkage:

      sqlite = project.frameworks_group.new_file("usr/lib/libsqlite3.tbd")
      sqlite.source_tree = "SDKROOT"
      app.frameworks_build_phase.add_file_reference(sqlite)

- [ ] Define the storage values in App/Search/SessionSearchDocument.swift:

      struct SessionSearchFingerprint: Equatable, Sendable {
          let path: String
          let modified: TimeInterval
          let sizeBytes: Int
      }

      struct SessionSearchDocument: Equatable, Sendable {
          let sessionPath: String
          let entryID: String?
          let projectPath: String
          let title: String
          let excerpt: String
          let kind: SearchResultKind
          let sessionModified: TimeInterval
          let entryOrder: Int
          let normalizedText: String
      }

- [ ] Add failing tests named sessionSearchDatabaseMatchesStoredMetadata, sessionSearchDatabaseSupportsCaseDiacriticsSubstringsAndShortQueries, sessionSearchDatabaseBindsQuotesAndPunctuationSafely, and sessionSearchDatabaseReplacesAndDeletesSessions. Use a unique temporary database URL and documents that cover session text, message text, tool argument keys and values, a path with spaces, résumé/RESUME, a mid-word substring, 1-character and 2-character queries, quotes, and punctuation.
- [ ] In the replacement test, assert that replacing one fingerprint removes its previous documents in the same transaction, preserves another session, orders newest sessions first and entries in file order, and limits output to 200.
- [ ] Regenerate the project and run the four focused tests. Confirm they fail because SessionSearchDatabase does not exist:

      ruby scripts/generate_xcodeproj.rb
      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-db-tests test '-only-testing:TenXAppTests/sessionSearchDatabaseMatchesStoredMetadata()' '-only-testing:TenXAppTests/sessionSearchDatabaseSupportsCaseDiacriticsSubstringsAndShortQueries()' '-only-testing:TenXAppTests/sessionSearchDatabaseBindsQuotesAndPunctuationSafely()' '-only-testing:TenXAppTests/sessionSearchDatabaseReplacesAndDeletesSessions()'

- [ ] Implement SessionSearchDatabase as the only SQLite C API boundary. Create exactly this version-1 schema:

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

- [ ] Keep the database wrapper surface focused:

      final class SessionSearchDatabase {
          static let schemaVersion = 1

          init(url: URL) throws
          func fingerprints() throws -> [String: SessionSearchFingerprint]
          func replace(
              fingerprint: SessionSearchFingerprint,
              documents: [SessionSearchDocument]
          ) throws
          func remove(sessionPaths: Set<String>) throws
          func search(normalizedQuery: String, limit: Int) throws -> [SearchResult]
      }

  The connection creates the approved indexed_session and trigram search_document tables, checks PRAGMA user_version, enables WAL and synchronous=NORMAL, finalizes every statement, and closes in deinit. Wrap prepare/bind/step/transaction failures in SessionSearchDatabaseError(operation:message:).
- [ ] For queries of at least three characters, escape embedded double quotes by doubling them, wrap the term in double quotes, and bind that string to MATCH. For one or two characters, bind the normalized term to instr(normalized_text, ?). Never interpolate user input into SQL.
- [ ] Set the database directory to owner-only permissions, the database to owner read/write, and exclude the database URL from backup. Tests pass an explicit temporary URL and do not touch Application Support.
- [ ] Rerun the four focused tests, then inspect regenerated project churn:

      git diff --check
      git diff -- scripts/generate_xcodeproj.rb 10x.xcodeproj/project.pbxproj

- [ ] Commit: feat(search): add persistent FTS storage

## Task 2: Index each changed session once

**Files:**
- Create: App/Search/SessionSearchDocumentBuilder.swift
- Modify: App/Search/SessionSearchService.swift
- Modify: Tests/TenXAppTests/SessionSearchServiceTests.swift

- [ ] Extend SessionSearchServiceTests with fixtures and failing tests named searchPreservesSessionMessageToolPathAndSubstringResults, unchangedSessionsAreParsedOnlyOnceAcrossQueries, unchangedSessionsSurviveServiceRecreationWithoutParsing, changedSessionsReplaceTheirIndexedDocuments, invalidChangedSessionKeepsPriorIndexedRows, removedSessionsLoseTheirIndexedDocuments, changingSourceDuringParseKeepsPriorRows, and corruptIndexRebuildsOnceFromSources.
- [ ] Inject a counting data loader into the service. In unchangedSessionsAreParsedOnlyOnceAcrossQueries, run two distinct queries against identical metadata and assert one source read. Recreate the service with the same database URL in unchangedSessionsSurviveServiceRecreationWithoutParsing and assert a warm query performs zero reads. In changedSessionsReplaceTheirIndexedDocuments, rewrite the fixture and supply a changed modified date or size, then assert the old term disappears and the new term appears after one additional read.
- [ ] For invalidChangedSessionKeepsPriorIndexedRows, seed valid rows, replace the source with invalid JSONL and changed metadata, and assert the prior result remains. For changingSourceDuringParseKeepsPriorRows, mutate the file from the injected loader before the post-parse attribute check and assert the old result remains. For corrupt recovery, write non-SQLite bytes at the explicit index URL and assert one reset/retry returns fixture results without altering the JSONL file.
- [ ] Run the eight new tests and confirm semantic failure against the current per-query parser:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-service-tests test '-only-testing:TenXAppTests/searchPreservesSessionMessageToolPathAndSubstringResults()' '-only-testing:TenXAppTests/unchangedSessionsAreParsedOnlyOnceAcrossQueries()' '-only-testing:TenXAppTests/unchangedSessionsSurviveServiceRecreationWithoutParsing()' '-only-testing:TenXAppTests/changedSessionsReplaceTheirIndexedDocuments()' '-only-testing:TenXAppTests/invalidChangedSessionKeepsPriorIndexedRows()' '-only-testing:TenXAppTests/removedSessionsLoseTheirIndexedDocuments()' '-only-testing:TenXAppTests/changingSourceDuringParseKeepsPriorRows()' '-only-testing:TenXAppTests/corruptIndexRebuildsOnceFromSources()'

- [ ] Move the current JSONValue traversal, result-kind selection, title, display text, excerpt, and normalization logic into SessionSearchDocumentBuilder. Its single entry point is:

      enum SessionSearchDocumentBuilder {
          static func documents(
              metadata: SessionMetadata,
              parsed: ParsedSessionFile
          ) throws -> [SessionSearchDocument]

          static func normalize(_ value: String) -> String
      }

  Produce the session document at entryOrder 0, followed by searchable message/tool documents in file order. Check Task cancellation between entries. Build normalizedText from the same fields the current search covers, including object keys and values. normalize folds case and diacritics and lowercases with Locale(identifier: "en_US_POSIX").
- [ ] Replace the service with a protocol-backed actor so SearchModalModel can be tested without SQLite:

      protocol SessionSearching: Sendable {
          func search(query: String, sessions: [SessionMetadata]) async -> [SearchResult]
      }

      actor SessionSearchService: SessionSearching {
          typealias DataLoader = @Sendable (URL) throws -> Data

          init(
              databaseURL: URL? = nil,
              loadData: @escaping DataLoader = { try Data(contentsOf: $0) }
          )

          func search(query: String, sessions: [SessionMetadata]) async -> [SearchResult]
      }

- [ ] Default databaseURL to Application Support/10x/SearchIndex-v1.sqlite. On a non-empty query, lazily open/recover the database, remove indexed paths absent from sessions, and process new/changed sessions one at a time. Compare path, modified.timeIntervalSince1970, and sizeBytes.
- [ ] Before parsing and before committing, check cancellation. Read one file, parse it once with SessionFileParser, then build documents with cancellation checks between entries and re-read file modification date and size from URLResourceValues. Commit only if they still match the metadata fingerprint. A read, parse, or drift failure preserves prior rows for that path.
- [ ] Treat CancellationError separately and return promptly without recovery or logging. Only an incompatible schema version or SQLite SQLITE_CORRUPT/SQLITE_NOTADB error may close the connection, delete the derived database plus -wal and -shm, reopen, and retry the complete operation once. On a second database failure, log [SearchIndex:<operation>] Search index unavailable — {sanitized message} and return an empty result.
- [ ] Run the focused service tests, including the service-recreation assertion, then commit:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-service-tests test '-only-testing:TenXAppTests/searchFindsSessionMessagesAndToolArguments()' '-only-testing:TenXAppTests/searchIsCaseAndDiacriticInsensitive()' '-only-testing:TenXAppTests/searchPreservesSessionMessageToolPathAndSubstringResults()' '-only-testing:TenXAppTests/unchangedSessionsAreParsedOnlyOnceAcrossQueries()' '-only-testing:TenXAppTests/unchangedSessionsSurviveServiceRecreationWithoutParsing()' '-only-testing:TenXAppTests/changedSessionsReplaceTheirIndexedDocuments()' '-only-testing:TenXAppTests/invalidChangedSessionKeepsPriorIndexedRows()' '-only-testing:TenXAppTests/removedSessionsLoseTheirIndexedDocuments()' '-only-testing:TenXAppTests/changingSourceDuringParseKeepsPriorRows()' '-only-testing:TenXAppTests/corruptIndexRebuildsOnceFromSources()'

- [ ] Commit: feat(search): index changed sessions once

## Task 3: Share and debounce the query service

**Files:**
- Modify: App/Application/AppDependencies.swift
- Modify: App/Application/AppModel.swift
- Modify: App/Shell/AppShellView.swift
- Modify: App/Search/SearchModalModel.swift
- Modify: App/Search/SearchModalView.swift
- Create: Tests/TenXAppTests/SearchModalModelTests.swift
- Modify: Tests/TenXAppTests/AppModelNavigationTests.swift

- [ ] Create a SearchSpy actor conforming to SessionSearching. It records query strings and returns deterministic results. Add failing main-actor tests named rapidQueryChangesDispatchOnlyTheFinalSearch, clearingQueryCancelsPendingSearch, staleSearchCannotReplaceCurrentResults, and openingSearchRefreshesSessions.
- [ ] In rapidQueryChangesDispatchOnlyTheFinalSearch, set 22 prefixes without waiting, advance a short injected debounce interval, and assert only the final string reached the spy. In staleSearchCannotReplaceCurrentResults, make the first spy response finish after the second and assert only the second result is installed.
- [ ] Run the focused tests and confirm current immediate dispatch/default service construction fails them:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-model-tests test '-only-testing:TenXAppTests/rapidQueryChangesDispatchOnlyTheFinalSearch()' '-only-testing:TenXAppTests/clearingQueryCancelsPendingSearch()' '-only-testing:TenXAppTests/staleSearchCannotReplaceCurrentResults()' '-only-testing:TenXAppTests/openingSearchRefreshesSessions()'

- [ ] Change SearchModalModel to require any SessionSearching and accept an injectable debounce Duration that defaults to .milliseconds(250). scheduleSearch cancels the old task, captures a monotonically increasing request ID, sleeps for the debounce duration, calls the service, and installs results only if the task is not cancelled and the request ID is still current. Clearing trims the query, clears state immediately, and cancels pending work. Emit fixed-name SearchQueryStarted and SearchQueryFinished points-of-interest signposts without query text so Release traces can count dispatches safely.
- [ ] Add let sessionSearch: SessionSearchService to AppDependencies and initialize exactly one instance in .live. Expose it from AppModel as a read-only any SessionSearching dependency for AppShellView.
- [ ] Make AppModel.openSearch set presentation state immediately and start Task { await reloadSessions() }. Pass the shared service through AppShellView to SearchModalView and into SearchModalModel. Modal recreation must not instantiate a service.
- [ ] Run the four focused tests, the complete app suite, and snapshot tests. No reference image should change because this task changes no UI:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-app-tests test
      git diff --exit-code -- Tests/TenXAppTests/ReferenceImages

- [ ] Commit: fix(search): debounce shared indexed queries

## Task 4: Release rebuild and repeat the baseline workload

**Files:**
- Create: docs/performance/2026-08-25-session-search.md
- Modify only if a requirement-backed defect is found in the files above.

- [ ] Regenerate the Xcode project and confirm there is no unintended project churn:

      ruby scripts/generate_xcodeproj.rb
      git diff --check

- [ ] Run the complete app suite and OmpKit suite. Record any repeatable pre-existing OmpKit process-lifecycle failure separately; do not change that subsystem:

      xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-final-tests test
      swift test --package-path OmpKit

- [ ] Build Release into a task-specific path:

      xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/tenx-search-release build

- [ ] Load launching-local-builds. Launch only /private/tmp/tenx-search-release/Build/Products/Release/10x.app, resolve its exact PID, and confirm that bundle is visible before profiling.
- [ ] Use the same 51-file, 21.7 MB corpus. Allow the first query to build the lazy index, then close and reopen search so the measured run is warm. Record settled idle CPU/RSS/physical footprint before the workload.
- [ ] Repeat the exact 22-prefix input cadence used by the baseline while recording process samples and a Time Profiler trace under /private/tmp/tenx-performance-recordings/fixed-search. Record dispatched query count, warm wall time, peak app CPU, RSS, physical footprint, and whether SessionFileParser.parse appears in the warm trace.
- [ ] Accept only if warm search is at most 100 ms, the 22-prefix workload dispatches one search, peak app CPU is below 15%, physical footprint stays below 125 MB, no warm parser stack appears, and idle returns to at most 1% CPU.
- [ ] Write docs/performance/2026-08-25-session-search.md with machine/OS/build identity, corpus dimensions, exact commands, baseline and fixed metrics in one table, trace filenames, and pass/fail against every threshold. Do not commit binary traces.
- [ ] Stop only the exact Release PID. Load verifying-work, rerun any evidence it identifies as stale, and inspect the final diff for scope.
- [ ] Commit: perf(search): record indexed search results

## Done When

- [ ] Every approved deterministic search case passes.
- [ ] Unchanged warm queries perform zero JSONL reads and zero SessionFileParser.parse work.
- [ ] The measured Release workload meets every CPU, memory, latency, idle, and dispatch threshold.
- [ ] Existing UI snapshots are unchanged; full app and OmpKit results are recorded honestly.
- [ ] The performance report contains reproducible before/after evidence and no binary profiling artifacts are committed.
