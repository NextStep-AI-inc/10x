# Turn file review correction

Status: DONE

## Root cause

OMP 18.1.10 returns multi-file cursor edits as one aggregate numbered `details.diff` plus authoritative `details.perFileResults`. `editCard` parsed the aggregate first without a fallback path, so the numbered parser collapsed both edits into one `Changed file` entry and the turn review list lost the real alpha and beta paths.

## Change

- When `details.perFileResults` is present, each result's `diff` is parsed with its matching `path` as the existing parser's fallback.
- The resulting files are combined under the original aggregate raw diff, preserving aggregate addition/removal totals and copy/render content.
- Payloads without `perFileResults` continue through the existing single-file, unified-diff, and AST paths.
- The turn regression reproduces repeated alpha editing, a multi-file alpha/beta edit, and a generated write. It verifies first-seen ordering, latest-tool mapping, and exact paths without a placeholder.

## Verified

- RED: `/tmp/10x-review-multifile-red.log` ran 2 tests with 3 expected issues. The extractor returned only `Changed file`; the turn list retained the old single-alpha tool, added `Changed file`, and omitted beta.
- GREEN: `/tmp/10x-review-multifile-green.log` ran the 2 new regressions with 0 failures.
- Focused compatibility: `/tmp/10x-review-multifile-focused.log` ran 14 tests with 0 failures. Coverage included the real multi-file shape, turn dedup/latest mapping, single-file result paths, standard unified diffs, numbered diffs, write references, and AST changed-file collections.
- `git diff --check` passed.

Command used `platform=macOS,arch=arm64`, `CODE_SIGNING_ALLOWED=NO`, and task-owned DerivedData at `/Users/tannerpham/Library/Developer/Xcode/DerivedData/10x-aeaprfrgcfzmarhgxipsdmykgcoj`.

## Not verified

- The signed Release native review flow was not rerun in this worker. Parent owns the rebuild and native acceptance.

## For parent to test

- Reopen the native review session and confirm the review list contains alpha, beta, and generated-note exactly once, with alpha and beta linked to the multi-file edit tool.
