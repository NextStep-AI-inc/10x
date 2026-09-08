# Active session audit evidence

The [HTML report](../../audits/2026-09-07-active-session-vs-t3-code.html) is the
review surface. This directory preserves its source evidence; it is not an
assertion that every pictured interaction was verified again.

## Evidence classes

| Files | What they establish | Limits |
| --- | --- | --- |
| `t3-*.jpg` | Historical browser captures from the prior audit of `t3@0.0.39` | Previously downscaled to 1200 px and encoded as JPEG. No fresh T3 interaction or restart test. |
| `originals/t3-*.png` | The 16 original browser PNGs corresponding to those JPEGs | Preserved byte for byte from the earlier capture output. |
| Historical `10x-*.png` | Reference images from `Tests/TenXAppTests/ReferenceImages` at `59a4ae8` | Real view rendering with synthetic fixture data, then downscaled to 1000 px. They do not establish live click, keyboard, timing, or persistence behavior. All 32 original reference PNGs examined matched this checkout. |
| `10x-recovered-window-current.png` | A current native screenshot of the still-running recovered Release audit process | Captured read-only through the native UI tool, with no new turn or navigation. Content is from the earlier audit. The build was not recompiled here. |
| `verify-warm-persistence.py` and `.output.txt` | Four current RPC cases against omp 18.1.10, with isolated fixtures/profile and zero model calls | Establishes RPC behavior, not an application quit/relaunch flow. |
| `omp-no-session-probe.py` and `.output.txt` | Historical diagnostic retained unchanged | The old script uses the caller's normal runtime/profile and its timeout loop is not a robust deadline. Prefer the new isolated probe. Historical blanket claims in its output are narrowed by the report. |

The file named `t3-approval-pending-02.jpg` does **not** show a successful pending
approval panel. The earlier Cursor/Supervised exercise did not produce one.
The 10x approval reference likewise is not a live approval capture.

## Current persistence result

```text
omp/18.1.10
new_session on --no-session: no sessionFile
new_session on persisting control: sessionFile present
switch_session on --no-session: File not found for the existing fixture
switch_session on persisting control: fixture message loaded; rename persisted
```

The switch failure corrects the historical claim that existing sessions load
normally but then lose new turns. The actual tested path fails before loading
the existing file. The disposable file remained unchanged in that failure case.

Reproduce from any directory:

```bash
python3 /path/to/verify-warm-persistence.py
```

The probe discovers `omp` and `bun`, with `OMP_EXECUTABLE` and `BUN_EXECUTABLE`
overrides available. It never sends a model prompt. It isolates
`PI_CODING_AGENT_DIR`, clears profile selection for its children, uses explicit
temporary session directories, terminates its own processes, and removes only
the temporary fixtures it created.

## Provenance and coverage

- [manifest.json](manifest.json) records all 30 report-image hashes, the
  original/source hashes, evidence classes, and the new native capture time.
- The 29 historical report images match both the recovered copies and the
  prior report-image output byte for byte.
- The original runtime was built from 10x
  `59a4ae8faaea049bfc2ff540a4f021b3859080b6`; reference source for T3 was
  `569a8cd2c3303f55fd869687eb31359b5658cc78`. T3 source and runtime are separately
  identified because source presence alone does not prove a captured feature.
- [The disposition index](../../audits/active-session-audit-coverage.json)
  accounts for all 90 recovered observations after duplicate merging,
  qualification, and correction. The count is not a bug count.
- Conversation history, private workflow journals, credentials, and prior
  assistant tool logs are not part of this deliverable.

The apps shared a scratch working directory in the historical run. Their edits
therefore changed each other's starting state. This evidence cannot support a
comparison of speed, model quality, or edit success.

The completed HTML report passed static image/link/source-reference checks.
Its rendered layout was not inspected: browser URL policy rejected the local
HTML file, and the workspace file preview was only queued. This limitation is
also stated in the report. No alternative browser route or local web server was
used after that policy rejection.
