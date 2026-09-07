# OMP Settings Editors — Design

Date: 2026-09-07
Status: Approved (brainstorming), pending implementation plan

## Problem

10x renders OMP settings from `omp config list --json` (484 settings on the
reference machine: 186 boolean, 122 number, 87 enum, 49 string, 29 array, 11
record). Three usability gaps:

1. **87 enum settings render as free-text fields.** The list JSON does not
   expose allowed values, so users must guess ("is it `max` or `ultra`?").
   Invalid values fail only at save time with a CLI error.
2. **Records and arrays-of-objects render as raw JSON text fields.** Nobody
   knows the required shape. Flagship case: `modelRoles` — the mapping of
   internal model roles (`default`, `plan`, `advisor`, `smol`, `commit`,
   `designer`, `slow`, `task`, `tiny`, `vision`) to `provider/model:effort`
   strings — is effectively uneditable in the GUI today.
3. **124 of 484 settings ship without a description**, so the row shows a
   label and a key with no explanation.

## Decisions (from brainstorming)

- Enum options and gap-fill descriptions are **hand-curated in 10x**, seeded
  once from the installed OMP package's shipped settings schema
  (`dist/types/config/settings-schema.d.ts` and the compiled bundle both
  contain the full schema: values, labels, descriptions, tab/group). After
  seeding, the table is maintained by hand; drift is caught by tests (below).
- Descriptions render as plain text with **no attribution**. OMP's own
  description always wins when present; curated text only fills true gaps.
- **No raw JSON editing anywhere.** Known record shapes get curated editors;
  unknown/future records get a generic key/value-row editor.

## Design

### 1. Curated metadata — `App/Settings/SettingMetadata.swift` (new)

Pure-data static table, keyed by setting key:

- `enumOptions: [String]` — allowed values for curated enums.
- `description: String` — gap-fill text, used only when OMP ships none.
- Record-editor kind for curated records (see §3).

`SettingsCatalog.build(from:)` merges it: OMP description wins, curated text
fills gaps, `enumOptions` attach to the definition. `SettingDefinition` gains
`enumOptions: [String]` (empty when uncurated). Search already covers
`description`, so gap-fill text becomes searchable automatically.

### 2. Enum control — dropdown + Other

In `SettingControlView`, an enum with non-empty `enumOptions` renders a
dropdown (saves immediately on selection, like the boolean toggle — no Apply
button) with the curated options plus an "Other…" item that reveals the
existing text field + Apply path. If the current value is not in the curated
list (OMP added a value, or the user set something exotic via CLI), it appears
as the selected custom value — never hidden, never coerced.

Enums without curated options keep the existing text field.

### 3. Record/array structured editors

Records never show raw JSON. Curated editors for the known shapes:

| Key | Editor |
| --- | --- |
| `modelRoles` | One row per role: model dropdown (from `OmpModelCatalogService`, the catalog the composer already uses) + effort dropdown for thinking-capable models. `:effort` suffix parsed out on read, re-joined on save. Roles can be added/removed. A current value whose model is absent from the catalog displays as-is (custom entry), never rewritten. |
| `tools.approval` | Rows: tool name → allow/prompt/deny dropdown. |
| `task.agentModelOverrides` | Rows: agent → model dropdown (same catalog source). |
| `providers.maxInFlightRequests` | Rows: provider → number field. |
| `retry.fallbackChains` | Rows: selector → ordered string list. |
| `task.agentAdvisor`, `task.agentPrewalk` | Rows: agent → value control matching the seeded schema's per-key value type (e.g. `agentAdvisor` values are an on/off-style enum). Exact value sets come from the seed extraction, not guesses. |
| everything else (`modelTags`, `statusLine.segmentOptions`, `images.urls.*`, future keys) | Generic key/value-row editor (scalar values), add/remove rows. |

Arrays of objects get a labeled mini-form per entry — concretely
`bashInterceptor.patterns` (pattern / tool / message fields per entry, add /
remove). Arrays of strings keep the existing list editor.

Booleans, numbers, and plain strings are unchanged.

### 4. Save/error flow

Unchanged: `SettingsViewModel.save` → `OmpConfigService.set`, per-key errors
surface via `keyErrors` under the row. Dropdown saves go through the same
path; OMP's server-side validation remains the backstop for anything the UI
got wrong.

## Testing

### Drift tests — `Tests/TenXAppTests/SettingMetadataDriftTests.swift` (new)

Mechanism verified against live OMP (2026-09-07, config left unmutated):

- `omp config set <enum-key> <sentinel>` exits 1 and prints
  `Error: Invalid value: <sentinel>. Valid values: minimal, low, …`.
- `omp config set <unknown-key> <anything>` exits 1 with `Unknown setting`.

The test, for every curated enum key: run the sentinel set, assert failure,
parse `Valid values:` from stderr, and diff against the curated table. A
removed/renamed key fails with "Unknown setting"; an added/removed/renamed
value fails the list diff. Every probe fails by construction, so the user's
config is never mutated. Opt-in integration test: skipped when no `omp`
binary is locatable.

### Unit tests

- Catalog merge: OMP description wins; curated fills gaps; options attach.
- Enum control: current value outside curated list surfaces as custom.
- `modelRoles` parsing: `provider/model:effort` split/join round-trip,
  missing effort, model absent from catalog.
- Record editors serialize back to the exact `JSONValue` shape OMP expects.

## Non-goals

- Adopting OMP's tab/group categorization (10x's prefix-based categories stay).
- Upstreaming descriptions to OMP.
- Parsing OMP's schema at runtime in the app.
- Changes to boolean/number/string controls.

## Out of scope / follow-ups

- The brainstorm mockups live in `.superpowers/brainstorm/` (gitignored) for
  reference.
