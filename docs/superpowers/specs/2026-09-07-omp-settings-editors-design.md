# OMP Settings Editors — Design

Date: 2026-09-07
Status: Approved (brainstorming + visual review), pending implementation plan

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
   strings — is effectively uneditable in the GUI today. Notably, OMP's own
   settings panel does not surface `modelRoles` either (no UI metadata in its
   schema); 10x will be the only GUI for it.
3. **124 of 484 settings ship without a description**, so the row shows a
   label and a key with no explanation.

## Source of truth: OMP's shipped schema

The installed package (`@oh-my-pi/pi-coding-agent`, verified on 18.1.10)
exposes its TypeScript source via `exports`, so the full settings schema is
importable with bun:

```bash
bun -e 'import { SETTINGS_SCHEMA } from ".../pi-coding-agent/src/config/settings-schema.ts"; ...'
```

For every one of the 484 settings this yields: `type`, `values` (enum value
lists), `default`, and `ui` metadata (`label`, `description`, `tab`, `group`,
and for many enums `options` with **human labels and per-option
descriptions** — e.g. `always-ask` → "Always ask — auto-approve read-only
tools"). This is the seed data for the curated tables below.

## Decisions (from brainstorming)

- Enum options are **seeded once from the installed OMP schema** (nothing
  guessed), then maintained by hand. Drift is caught by tests (see Testing).
  Note: the schema's descriptions exactly match `config list --json` output —
  the 124 undocumented keys are undocumented in the schema too (they carry no
  `ui` block), so gap-fill descriptions are **hand-written** for the
  user-facing subset (e.g. `modelRoles`, `cycleOrder`, `enabledModels`,
  `shellPath`); internal keys stay blank.
- Descriptions render as plain text with **no attribution**. OMP's own
  description always wins when present; curated text only fills true gaps.
- **No raw JSON editing anywhere.** Known record shapes get curated editors;
  unknown/future records get a generic key/value-row editor.

## Design

### 1. Curated metadata — `App/Settings/SettingMetadata.swift` (new)

Pure-data static table, keyed by setting key:

- `enumOptions: [SettingOption]` — value + optional human label + optional
  per-option description, seeded from the schema's `ui.options`.
- `description: String` — gap-fill text, used only when OMP ships none.
- Record-editor kind / array value-set metadata where curated (§3, §4).

`SettingsCatalog.build(from:)` merges it: OMP description wins, curated text
fills gaps, options attach to the definition. `SettingDefinition` gains
`enumOptions: [SettingOption]` (empty when uncurated). Search already covers
`description`, so gap-fill text becomes searchable automatically.

### 2. Enum control — dropdown + Other

An enum with non-empty `enumOptions` renders a dropdown that saves
immediately on selection (no Apply button, like the boolean toggle).

- **Closed state:** same underline-field look as today's text fields (mono 11
  value, 1px near-black bottom rule) plus a cyan chevron at the trailing edge.
- **Open state:** popover below the field, one row per option — human label
  (body 12 medium) + per-option description (muted 10) when the schema
  provides them, raw mono value otherwise; cyan checkmark on the current
  value; hover uses `hoverNeutralHex`. "Other…" pinned at the bottom reveals
  the existing text field + Apply path.
- **Custom value:** if the current value is not in the curated list (OMP
  added a value, or the user set something exotic via CLI), it shows as the
  selected value with a "custom" marker — never hidden, never coerced.

Enums without curated options keep the existing text field.

### 3. Record editors — full-width, never raw JSON

Records and object-arrays **break out of the 300px control column**: the row
renders label/description/key on top and the editor full-width below.

| Key | Editor |
| --- | --- |
| `modelRoles` | One row per role: role name, model dropdown (from `OmpModelCatalogService`, the catalog the composer already uses), effort dropdown for thinking-capable models. `:effort` suffix parsed out on read, re-joined on save. "+ Add role" offers known roles not yet set. A current value whose model is absent from the catalog displays as-is (custom entry), never rewritten. Save writes the whole record (OMP rejects nested keys like `modelRoles.default` — verified); removing all rows resets to OMP defaults. |
| `tools.approval` | Rows: tool name → allow/prompt/deny dropdown. |
| `task.agentModelOverrides` | Rows: agent → model dropdown (same catalog source). |
| `providers.maxInFlightRequests` | Rows: provider → number field. |
| `retry.fallbackChains` | Rows: selector → ordered string list. |
| `task.agentAdvisor`, `task.agentPrewalk` | Rows: agent → string value (schema type `Record<string, string>`; `agentAdvisor` currently `{"task": "on"}`). |
| `modelTags`, `statusLine.segmentOptions`, `images.urls.options`, `images.urls.credentials` | Generic key/value-row editor (scalar values; `credentials` values masked). Also the fallback for any future record OMP adds. |

### 4. Array editors — four treatments

- **Object array mini-form** (1 key): `bashInterceptor.patterns` — bordered
  card per entry with labeled underline fields (pattern / tool / message),
  add/remove. Pattern validated as a compilable regex before save.
- **Known-set, reorderable** (4 keys): `cycleOrder` (model role names),
  `compaction.methodOrder`, `providers.webSearchOrder`, `providers.imageOrder`
  — rows with value + remove + up/down reorder, plus an add-from-dropdown
  listing set members not yet present. Sets are seeded only where OMP's source
  enumerates them (verified extractable from the installed package).
- **Catalog-fed id lists** (4 keys): `enabledModels`, `modelProviderOrder`,
  `enabledProviders`, `disabledProviders` — add-from-picker fed by the live
  model/provider catalog instead of typing ids.
- **Free-form string lists** (20 keys): `bash.patterns`, `extensions`,
  `disabledExtensions`, `skills.*`, `shellMinimizer.only/except`,
  `task.disabledAgents`, `workspace.additionalDirectories`,
  `ttsr.disabledRules`, `statusLine.leftSegments/rightSegments`,
  `goal.continuationModes`, `hindsight.recallTypes`, `images.urls.backends`,
  etc. — existing list editor, unchanged. (These have no enumerable domain in
  OMP's source; if OMP later exposes one, promote them to known-set.)

### 5. Unchanged

Booleans (toggle), numbers (field), plain strings (field), search,
categories, section layout, and the per-key error surfacing via
`SettingsViewModel.keyErrors`.

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
- Record editors serialize back to the exact `JSONValue` shape OMP expects
  (whole-record write).

## Non-goals

- Adopting OMP's tab/group categorization (10x's prefix-based categories stay).
- Upstreaming descriptions to OMP.
- Parsing OMP's schema at runtime in the app (seed extraction is a one-time
  dev action; the shipped table is plain Swift data).
- Changes to boolean/number/string controls.

## Reference material

- Brainstorm mockups (current-vs-proposed, inventory, visual wrappers):
  `.superpowers/brainstorm/` (gitignored).
- Extracted schema dump used for seeding: regenerate with the bun one-liner
  above against the installed OMP package.
