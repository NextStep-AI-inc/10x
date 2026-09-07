// Seed generator for App/Settings/SettingMetadata.swift.
// Reads the installed OMP package's settings schema and `omp config list --json`,
// then emits plain Swift data: enum options (with human labels/descriptions) and
// known array value sets. Rerun when OMP updates; SettingMetadataDriftTests flag
// drift against the installed omp binary.
//
// Usage: bun scripts/seed_setting_metadata.ts > App/Settings/SettingMetadata.swift

import { homedir } from "node:os";

const PKG = `${homedir()}/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent`;
const OMP = `${homedir()}/.bun/bin/omp`;

const { SETTINGS_SCHEMA } = await import(`${PKG}/src/config/settings-schema.ts`);
const { COMPACTION_METHOD_CHOICES } = await import(`${PKG}/src/session/compaction-methods.ts`);
const { SEARCH_PROVIDER_CHOICES } = await import(`${PKG}/src/web/search/types.ts`);
const { IMAGE_PROVIDER_CHOICES } = await import(`${PKG}/src/tools/image-providers.ts`);

const listProc = Bun.spawnSync([OMP, "config", "list", "--json"]);
const listed = JSON.parse(listProc.stdout.toString());

// Model roles OMP defines (from modelRoles' shape; not enumerated in the schema).
const MODEL_ROLES = ["default", "plan", "advisor", "smol", "commit", "designer", "slow", "task", "tiny", "vision"];

const esc = (s: string): string =>
  s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");

const swiftOpt = (v: string, label?: string | null, detail?: string | null): string => {
  const parts = [`"${esc(v)}"`];
  if (label && label !== v) parts.push(`label: "${esc(label)}"`);
  if (detail) parts.push(`detail: "${esc(detail)}"`);
  return `SettingOption(${parts.join(", ")})`;
};

const enumLines: string[] = [];
for (const [key, def] of Object.entries(SETTINGS_SCHEMA) as [string, any][]) {
  if (def.type !== "enum") continue;
  const opts = Array.isArray(def.ui?.options) && def.ui.options.length
    ? def.ui.options.map((o: any) => swiftOpt(o.value, o.label, o.description))
    : (def.values ?? []).map((v: string) => swiftOpt(v));
  if (opts.length) {
    enumLines.push(`        "${esc(key)}": [\n            ${opts.join(",\n            ")},\n        ],`);
  }
}

const knownArrays: [string, string[]][] = [
  ["cycleOrder", MODEL_ROLES],
  ["compaction.methodOrder", COMPACTION_METHOD_CHOICES.map((c: any) => c.value)],
  ["providers.webSearchOrder", SEARCH_PROVIDER_CHOICES.map((c: any) => c.value)],
  ["providers.imageOrder", IMAGE_PROVIDER_CHOICES.map((c: any) => c.value)],
];
const arrayLines = knownArrays.map(([key, values]) =>
  `        "${esc(key)}": [${values.map((v) => `"${esc(v)}"`).join(", ")}],`);

console.log(`import Foundation

// Seeded from OMP's shipped settings schema by scripts/seed_setting_metadata.ts.
// Hand-maintain from here; SettingMetadataDriftTests flag drift against the
// installed omp binary.

struct SettingOption: Equatable {
    let value: String
    var label: String? = nil
    var detail: String? = nil

    init(_ value: String, label: String? = nil, detail: String? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
    }
}

enum SettingMetadata {
    static let enumOptions: [String: [SettingOption]] = [
${enumLines.join("\n")}
    ]

    /// Gap-fill text for keys whose omp config list entry ships no description.
    /// OMP's own runtime description always wins when present. Hand-written;
    /// the schema documents no keys beyond what config list already reports.
    static let descriptions: [String: String] = [:]

    /// Closed value sets for array settings, where OMP's source enumerates them.
    static let knownArrayValues: [String: [String]] = [
${arrayLines.join("\n")}
    ]

    /// Array keys whose values come from the live model/provider catalog.
    static let catalogFedArrays: Set<String> = [
        "enabledModels", "modelProviderOrder", "enabledProviders", "disabledProviders",
    ]
}
`);
