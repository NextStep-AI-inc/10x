# Composer Session Controls (Model, Thinking, Fast)

**Status:** Approved for implementation planning  
**Date:** 2026-08-25  
**Platform:** macOS 15+, Swift 6.1, SwiftUI  
**OMP contract:** 18.0.4+

## Goal

The new-session and active-session composers share one control surface so the
user can pick the model (among signed-in providers), thinking level, and fast
mode (when the current model supports it) without leaving the footer.

Today those footer chips (`GPT-5.6`, `High`, and the missing Fast control) are
inert stubs. This work makes them real against OMP’s existing RPC and config
contracts. It does not invent app-side defaults that drift from the CLI/TUI.

## Approved product decisions

- Controls: **Model**, **Thinking**, and **Fast** (when supported). **Local**
  stays an inert stub.
- Same shared component for **new session** and **active session**.
- Layout: **separate ghost buttons**, each with its own native menu/toggle.
- Catalog: no-session RPC (`get_available_models` + `get_state`).
- Model menu: **authenticated providers only**, flat list, no search in v1.
- Defaults: **match OMP** (`modelRoles.default`, `defaultThinkingLevel` via
  `get_state` / config). No UserDefaults for model/thinking/fast.
- New-session model/thinking writes update OMP settings so the next blank
  session and the CLI stay aligned.
- Active-session picks use live `set_*` only and do **not** rewrite
  `modelRoles`.
- Fast mode is OMP’s priority service-tier toggle (`set_fast_mode`), not the
  `-fast` model id suffix. Hide the chip when unavailable.
- Work proceeds on `main` for quick iteration (explicit exception to the
  usual worktree rule for this task).

## User flow

```text
New Session canvas
  |
  v
Composer footer: Project · Local · Model · Thinking · [Fast?]
  |
  |-- pick model/thinking --> persist OMP default --> labels update
  |-- toggle Fast ----------> pending intent until first prompt
  |
  v
Start session
  openNew(--provider --model --thinking)
  optional set_fast_mode(true)
  |
  v
Active session composer (same controls)
  set_model / set_thinking_level / set_fast_mode
  labels follow get_state / config_update
```

Returning to New Session re-seeds from no-session `get_state` (OMP defaults),
not from the last live session’s temporary model.

## Architecture

```text
SwiftUI
├── ComposerView
│   └── ComposerSessionControlsView
└── NewSessionView / ActiveSessionView
        |
        v
AppModel
 └── ComposerControlsModel          @MainActor @Observable
      ├── OmpModelCatalogService    no-session get_available_models + get_state
      ├── OmpConfigService          persist modelRoles.default / thinking default
      └── SessionController bridge  live set_model / set_thinking_level / set_fast_mode
```

`ComposerControlsModel` follows the same ownership pattern as
`ProviderManagementViewModel`: constructed when OMP is installed, refreshed on
foreground / route entry, shut down with the app’s provider/session teardown.

`RpcClientConfiguration` gains optional spawn flags (`provider`, `model`,
`thinking`) so `SessionProcessManager.openNew` can pass them through. Fast mode
is applied after the child is ready because it is not a spawn argv flag.

### Why not put this on SessionController

A draft controller before process start mixes pre-session catalog/config work
into the live runtime type. A dedicated feature model keeps session process
lifecycle unchanged and mirrors the provider feature split already in the app.

## UI

Shared `ComposerSessionControlsView` in the composer footer:

| Control | Presentation | Behavior |
|---------|--------------|----------|
| Model | Ghost chip labeled with display name | Flat `Menu` of models from authenticated providers |
| Thinking | Ghost chip labeled with level (including Auto) | `Menu` of levels from the selected model’s `thinking.efforts` (+ Auto when OMP allows). Hidden or disabled when the model has no thinking metadata |
| Fast | Ghost chip, accent when on | Toggle. Shown only when the current model’s service-tier family supports `set_fast_mode` |
| Local | Existing stub | Unchanged, inert |

Menus use native SwiftUI `Menu` / toggle affordances, not custom popovers.

Loading: chips show last known labels (or short placeholders); menus disabled
until the catalog arrives.

Errors: one-line message under the footer row. No modal.

Copy register: functional labels only (`Model`, thinking level names, `Fast`).
No marketing language.

## Data flow

### Bootstrap

1. No-session client: `get_state` → current model, `thinkingLevel`,
   `fastModeEnabled` / `fastModeActive`.
2. `get_available_models` → catalog.
3. Intersect catalog providers with authenticated `get_login_providers`
   results (reuse the provider model’s auth list when already loaded).
4. Thinking options come from the selected model’s `thinking.efforts`
   (and Auto when configured).

### New session selection

| User action | Persist | Apply at start |
|-------------|---------|----------------|
| Pick model | `omp config set` `modelRoles.default` to `provider/modelId` (including OMP’s thinking suffix encoding when that is how the role is stored) | `--provider` + `--model` on `openNew` |
| Pick thinking | Update OMP thinking default (`defaultThinkingLevel` and/or role encoding, whichever OMP already uses for that model) | `--thinking` on `openNew` when applicable |
| Toggle Fast | **Session intent only** until spawn (no global fast key in config today) | After open: `set_fast_mode(true)` if intent is on |

If persist fails, the UI selection does not change and the error is shown.
Do not start a session with labels that disagree with what will be spawned.

### Active session selection

| User action | Effect |
|-------------|--------|
| Pick model | `set_model(provider, modelId)` on the live client. Do not write `modelRoles`. |
| Pick thinking | `set_thinking_level(level)`. |
| Toggle Fast | `set_fast_mode(enabled)`. On unsupported: hide chip, clear intent, show brief error. |

Labels sync from command responses and `config_update` / `get_state`.

### Leaving an active session

`ComposerControlsModel` re-seeds from no-session `get_state` so New Session
shows OMP defaults again.

## Error handling

- Catalog load failure: keep last known labels or placeholders; disable menus;
  show one-line error; retry on New Session entry / foreground refresh.
- Config persist failure: leave selection unchanged; show error.
- Live `set_*` failure: revert chips to previous session state; show sanitized
  OMP error string.
- Model switch that drops fast support: hide Fast; clear pending fast intent.
- While a set/persist is in flight: disable the control menus (same idea as
  provider login row disable).

## Testing

Smallest checks that fail if the logic breaks:

- Catalog filter keeps only authenticated providers.
- Thinking options derived from model metadata; empty → control hidden/disabled.
- Fast visibility gated on support; unsupported `set_fast_mode` hides the chip.
- New-session apply builds spawn flags and optional post-open `set_fast_mode`.
- Active path sends `set_*` and does not call config persist for `modelRoles`.
- Failed persist leaves selection unchanged.
- Snapshot: composer footer with Fast present and absent.

## Out of scope

- Local / execution mode control
- Searchable or full unauthenticated catalog
- App UserDefaults for model/thinking/fast defaults
- Persisting Fast as a global OMP setting (unless a real config key is found
  later)
- Logout, provider setup, or usage ledger changes

## Implementation notes (non-normative)

- Decode the opaque `Model` JSON fields needed for UI: `id`, `name`,
  `provider`, `thinking` (`efforts`, `requiresEffort`, `effortRouting`).
- Reuse the existing no-session RPC client pool pattern from
  `ProviderManagementService` where practical; do not spawn a second idle
  omp child if one can be shared safely.
- Extend `RpcClientConfiguration.resolvedArguments` for `--provider`,
  `--model`, and `--thinking` in the same order as the RPC client port spec.
- Confirm the exact `omp config set` key/value shape for role + thinking
  against live OMP 18.x during implementation; prefer writing the same form
  `get_state` / `config.yml` already use (`provider/modelId` and optional
  `:effort` suffix).
