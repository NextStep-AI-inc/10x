# SDD ledger — plan: /Users/tannerpham/CS Projects/.worktrees/10x-computer-use-design/docs/superpowers/plans/2026-08-25-tenx-agent-desktop.md

## Execution context

- Worktree: `/Users/tannerpham/CS Projects/.worktrees/10x-computer-use-design`
- Branch: `codex/computer-use-design`
- Starting SHA: `30be0be`
- Remote: none. Ruling: local atomic commits only; a draft PR cannot be opened from this repository state.
- Upstream dependency: complete and approve all four OMP tasks before dispatching 10x Task 1.
- Untouched baseline: `swift test` in `OmpKit` passed 125 tests with 2 integration tests skipped; `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-baseline` passed 94 app tests. Xcode emitted non-fatal `linkd.autoShortcut` registration noise already present at baseline.
- Approved local OMP prerequisite: branch `codex/computer-foreground-handoff`, SHA `97f8d190040ccd49b4509b98eedf5b445dad1ce2`, executable `/Users/tannerpham/CS Projects/.worktrees/oh-my-pi-computer-foreground-handoff/packages/coding-agent/dist/omp`. Binary reports `omp/18.0.5` and `--smoke-test` returns `ok`. Full OMP suite retains the independently reproduced upstream HTML golden mismatch; focused contract/type/format gates pass.

## Preflight self-consistency scan

| Task | Finding | Ruling |
|---|---|---|
| 1 | OMP wire support is an external versioned prerequisite. | Decode the exact approved command/frame shapes, expose an explicit incompatible-version result, and never silently fall back to ungated computer use. |
| 1 | New typed `RpcFrame` host-tool cases make the existing `RpcClient` switch non-exhaustive, but `RpcClient.swift` was omitted from the task header. | Ownership fence extended only to pass the new frame cases through the existing event stream; no unrelated client changes. |
| 2 | A process-wide registry alone cannot protect another 10x process. | Keep the registry for same-process ownership and the advisory lease for cross-process exclusion; both must be covered separately. |
| 3 | AeroSpace and Hammerspoon are user-managed helpers. | Detect and call them through the bounded runner; never install them or edit user configuration. The bundled Hammerspoon template is copied/shown only by explicit setup action. |
| 3 | The brief asks `AgentDesktopCoordinator.cleanup(manifest:)` to consume `AgentDesktopManifest`/`CleanupReport`, but Task 4 explicitly produces those canonical types. | Do not create Task-3-local placeholder forms. Task 3 implements prepare/readiness/probe/provider seams; Task 4 adds cleanup once it owns the manifest/report types. |
| 4 | macOS does not provide a reliable generic dirty-document signal for every external app. | Claim only newly observed window IDs; restore moved windows, but never close external windows automatically in V1. |
| 5 | Partial OMP setup could leave a computer tool enabled without a safe desktop. | Enable as a transaction and fail closed: register host tool, prepare provider/lease, set `require-handoff`, reconcile state; unwind every completed step on failure. |
| 6 | The setup probe includes a background text mutation. | Use only the 10x-owned disposable probe window and exact verification text; capability-only probing remains non-mutating. |
| 7 | Computer screenshots must survive live/history reducer paths. | Persist/decode the existing tool result payload without a second media pipeline; render missing/corrupt images as an explicit card state. |
| 8 | Foreground handoff and emergency stop are safety controls. | One approval maps to one OMP request ID; Stop, lock, sleep, helper failure, controller teardown, and hotkey all converge on the same fail-closed stop path. |
| 9 | Unit tests cannot establish the non-interruption guarantee. | Verify a Release build through the real UI and record which physical desktop cases were observed; do not claim unperformed manual cases. |

## Preflight pairwise conflict scan

| Tasks | Shared file/interface | Ruling |
|---|---|---|
| 1–4 | Typed host-tool definitions consumed by `AgentDesktopHostTool`. | Task 4 must use Task 1 wire types rather than define a parallel JSON shape. |
| 1–5 | Computer RPC commands/state and host-tool frames. | Task 5 consumes Task 1 APIs unchanged; protocol corrections return to Task 1's seam with regression coverage. |
| 1–6 | Disposable `probe_computer_use` contract. | Task 6 uses the typed probe and does not invoke model code. |
| 1–8 | `computer_foreground_handoff` request/response. | Task 8 routes the exact request ID and typed decision; no optimistic approval state. |
| 1–9 | Complete OMP public contract. | Acceptance verifies version gate, enable/reconcile, probe, host tool, and handoff together. |
| 2–3 | Generated Xcode project. | Execute sequentially and regenerate from current HEAD; never hand-merge generated project entries. |
| 2–4 | Generated Xcode project. | Regenerate after Task 4 using Task 2's checked-in baseline. |
| 2–5 | Lease/registry APIs plus generated project. | Task 5 uses both ownership layers and does not bypass either. |
| 2–6 | Generated Xcode project. | Regenerate after Task 6; do not alter Task 2 state semantics from UI code. |
| 2–7 | Generated Xcode project. | Regenerate after Task 7; tool evidence remains independent of ownership state. |
| 2–8 | Computer-use state/registry plus generated project. | Task 8 observes the controller/registry public state and routes all shutdown through the controller. |
| 2–9 | Ownership invariants. | Acceptance includes same-process replacement and cross-process denial evidence. |
| 3–4 | `AgentDesktopCoordinator`, provider interfaces, generated project. | Task 4 extends the public provider seam only; provider-specific branching stays in Task 3 implementations. |
| 3–5 | Prepared desktop/coordinator plus generated project. | Task 5 owns lifecycle orchestration, while Task 3 remains helper selection/execution. |
| 3–6 | Provider probes and generated project. | Task 6 consumes readiness results without duplicating helper commands. |
| 3–7 | Generated Xcode project. | Regenerate from current HEAD; no provider logic belongs in tool presentation. |
| 3–8 | Helper failure lifecycle plus generated project. | Surface failures through the controller stop path; do not add a second watcher in UI. |
| 3–9 | Desktop isolation providers. | Acceptance distinguishes AeroSpace, Hammerspoon, and background-only capabilities. |
| 4–5 | Manifest/host tool plus generated project. | Task 5 calls Task 4 ownership operations and owns rollback sequencing, not window identity rules. |
| 3–5 | Task 5 requires provider release, but Task 3 exposed provider `release` only behind the protocol and omitted a coordinator forwarding seam. | Task 5 may narrowly add `AgentDesktopCoordinator.release(_:)` plus a forwarding test; provider-specific behavior remains unchanged. |
| 1–5 | Task 5 must confirm process death before releasing the cross-process lease, but the existing OmpKit shutdown APIs discard the transport's final exit result. | Task 5 may narrowly extend `LineTransport`/`RpcClient`/`SessionProcessManager` with a deadline-aware, confirmed-dead shutdown result plus focused OmpKit tests; normal callers retain existing behavior. |
| 4–6 | Generated Xcode project. | Regenerate; setup UI must not claim or clean real external windows. |
| 4–7 | Generated Xcode project. | Regenerate; transcript presentation cannot mutate manifests. |
| 4–8 | Claimed-window lifecycle plus generated project. | Stop restores claims conservatively and leaves external windows open. |
| 4–9 | Launch/borrow/cleanup contract. | Acceptance verifies only new IDs are claimed and pre-existing windows are untouched. |
| 5–6 | `AppModel`, controller readiness, generated project. | Task 6 exposes controller/setup actions through existing dependency ownership; no duplicate controller instance. |
| 5–6 | Persisted Task 6 provider preference must reach Task 5's per-session controller, but `SessionController` and `AppDependencies.makeSessionController` expose no preference parameter. | Task 6 may narrowly extend both initializer/factory signatures plus existing factory tests to pass the current `AgentDesktopPreference`; no controller lifecycle logic changes. |
| 5–7 | Generated Xcode project. | Regenerate; lifecycle state and tool-card state stay separate. |
| 5–8 | `AppModel`, `SessionController`, controller APIs, generated project. | Task 8 extends existing lifecycle hooks and uses one controller per session. |
| 5–9 | Complete enable/stop lifecycle. | Acceptance verifies transactional unwind and state reconciliation. |
| 6–7 | Snapshot test harness/reference images plus generated project. | Update the shared snapshot registry without replacing unrelated baselines. |
| 6–8 | `AppModel`, snapshot harness/reference images, generated project. | Reuse settings state and preserve Task 6 baselines while adding handoff/header states. |
| 6–9 | Setup/readiness flow. | Acceptance begins from the real setup surface and records degraded-state behavior. |
| 7–8 | `TranscriptView`, snapshot harness/reference images, generated project. | Compose the handoff card and computer evidence without forking transcript layout. |
| 7–9 | Computer tool evidence. | Acceptance verifies live and reopened-session images/cards. |
| 8–9 | Foreground handoff and fail-closed controls. | Acceptance exercises approve, cancel, Stop, menu bar, hotkey, lock/sleep when safely available. |

## Task status

| Task | Status | Base | Head | Review | Notes |
|---|---|---|---|---|---|
| 1. OmpKit Computer RPC Contract and Version Gate | complete | `30be0be` | `430bd543daca668c72186de910f5f0bf8b2f55a3` | Approved after fix round 1 | Commits `95134d2`, `430bd54`; 136 tests pass, 2 existing environment-gated skips. |
| 2. Computer State Machine, Lease, and Same-Process Registry | complete | `430bd543daca668c72186de910f5f0bf8b2f55a3` | `e51a6347b4be38f727741f8880ea2a48d7cda532` | Approved after fix round 3 | Commits `f17b8c5`, `0263ec9`, `d55f1fd`, `e51a634`; 109 app tests pass. |
| 3. Provider Selection and Safe Helper Runner | complete | `e51a6347b4be38f727741f8880ea2a48d7cda532` | `839ddf830fdcf80aabc67e7b8371cd74ab39ba1e` | Approved after fix round 2 | Commits `ed2e5fa`, `4a23bb8`, `839ddf8`; 127 app tests pass. External helpers remain acceptance work. |
| 4. Dedicated Window Claims and Conservative Manifest Cleanup | complete | `839ddf830fdcf80aabc67e7b8371cd74ab39ba1e` | `ac0e6abef95c8e41e7e4ebf2053271125d6fccb5` | Approved after fix round 2 | Commits `bc65a0c`, `7df434e`, `ac0e6ab`; 146 Debug tests and Release app build pass. Live external-app behavior remains Task 9 acceptance. |
| 5. Per-Session Controller and OMP Lifecycle Integration | complete | `ac0e6abef95c8e41e7e4ebf2053271125d6fccb5` | `b905c92c6bb0458e3698a1b0b9eb9b647d411d9c` | Approved after stronger rounds 4–8 | Commits through `b905c92`; OmpKit 165 pass, app 174 pass, universal Release build passes. |
| 6. Specialized Setup and Readiness UI | complete | `b905c92c6bb0458e3698a1b0b9eb9b647d411d9c` | `b4b9744f5f03008e043828b9ed8849fe42bd4460` | Approved after fix round 4 | Commits through `b4b9744`; app tests 190 pass, Release build passes, and placement outcomes distinguish cancellation, non-applicability, failure, and success. |
| 7. Computer Tool Evidence and Persisted Images | complete | `b4b9744f5f03008e043828b9ed8849fe42bd4460` | `4711e0f` | Approved after owner fix round 1 | Commits `c0658ce`, `4711e0f`; app tests 200 pass, Release build passes, reference images inspected. |
| 8. Foreground Handoff, Header Controls, Menu Bar Stop, and Fail-Closed Lifecycle | complete | `6d97ff5` | `59e90407b129818bb1d41858240b5b95da8b2ff7` | Approved by code-owner review | Commit `59e9040`; app tests 210 pass, universal Release build passes, and handoff/ready/controlling snapshots inspected. |
| 9. Release-Build End-to-End Acceptance | recorded with blocked physical acceptance | `09a3215` | `3f76216` | Pending whole-branch review | Automated gates passed after timing-sensitive reruns and the Release app launched visibly. Older OMP 18.0.4 gating passed in the real settings UI; AeroSpace, Hammerspoon, and Background Only live agent runs remain recorded as FAIL/not run because required local prerequisites were unavailable. |

## Rulings and follow-ups

- No dependency installation, deployment, merge, or publication is authorized by this execution.
- The approved visual system and current component patterns are binding; snapshot updates must be inspected, not blindly accepted.
- Task 9: Ruling: acceptance documentation records failed/not-run physical desktop rows instead of manufacturing pass evidence. The environment does not expose `aerospace` and Hammerspoon is not installed; older OMP 18.0.4 gating was observed in the real Release UI. Cost: AeroSpace, Hammerspoon, and Background Only still require a follow-up acceptance pass on a configured desktop before the branch can be called release-ready.
