// Seed generator for App/Settings/SettingMetadata.swift.
// Reads the installed OMP package's settings schema and emits plain Swift data:
// enum options (with human labels/descriptions) and known array value sets.
//
// Usage: bun scripts/seed_setting_metadata.ts  (run from repo root)
//
// One-shot seed — after hand-edits land (e.g. descriptions), do NOT re-run;
// re-running wipes hand-written copy. SettingMetadataDriftTests are the update
// signal when OMP's schema drifts from the committed file.

import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const PKG = `${homedir()}/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent`;
const OUT = join(import.meta.dir, "..", "App", "Settings", "SettingMetadata.swift");

if (!existsSync(PKG)) {
  console.error(`error: OMP package not found at ${PKG}`);
  process.exit(1);
}

const { SETTINGS_SCHEMA } = await import(`${PKG}/src/config/settings-schema.ts`);
const { COMPACTION_METHOD_CHOICES } = await import(`${PKG}/src/session/compaction-methods.ts`);
const { SEARCH_PROVIDER_CHOICES } = await import(`${PKG}/src/web/search/types.ts`);
const { IMAGE_PROVIDER_CHOICES } = await import(`${PKG}/src/tools/image-providers.ts`);

// Model roles OMP defines (from modelRoles' shape; not enumerated in the schema).
const MODEL_ROLES = ["default", "plan", "advisor", "smol", "commit", "designer", "slow", "task", "tiny", "vision"];

const esc = (s: string): string => {
  let out = "";
  for (const ch of s) {
    const code = ch.charCodeAt(0);
    if (code < 0x20) {
      if (ch === "\n") out += "\\n";
      else if (ch === "\r") out += "\\r";
      else throw new Error(`control char U+${code.toString(16).padStart(4, "0")} in ${JSON.stringify(s)}`);
    } else if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else out += ch;
  }
  return out;
};

const swiftOpt = (v: string, label?: string | null, detail?: string | null): string => {
  const parts = [`"${esc(v)}"`];
  if (label && label !== v) parts.push(`label: "${esc(label)}"`);
  if (detail) parts.push(`detail: "${esc(detail)}"`);
  return `SettingOption(${parts.join(", ")})`;
};

const enumLines: string[] = [];
for (const [key, def] of (Object.entries(SETTINGS_SCHEMA) as [string, any][]).sort(([a], [b]) =>
  a.localeCompare(b),
)) {
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

const output = `// Seeded from OMP's shipped settings schema by scripts/seed_setting_metadata.ts.
// Hand-maintain from here; SettingMetadataDriftTests flag drift against the
// installed omp binary.

struct SettingOption: Equatable {
    let value: String
    let label: String?
    let detail: String?

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
        "enabledModels", "modelProviderOrder", "disabledProviders",
    ]
}
`;

await Bun.write(OUT, output);

if (esc('"') !== '\\"') throw new Error("esc quote");
if (esc("\\") !== "\\\\") throw new Error("esc backslash");
if (esc("\n") !== "\\n") throw new Error("esc newline");
if (esc("\r") !== "\\r") throw new Error("esc CR");
