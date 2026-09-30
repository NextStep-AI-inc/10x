# Repair the merge-blocking test suite

Goal: diagnose and repair the failing tests on the existing dock branch, preserve the approved UI and main changes, then finish the authorized merge only after verification is green.

Baseline: product 2670110, report 3ed1ccb. Full run: 1,714 tests, 44 suites, 188 issues (180 snapshot mismatches, 8 functional assertions across five tests). Logs in /tmp/10x-main-integration-tests.log; current actual images beside references.

1. Investigate snapshot differences at the pixel level. Separate rendering drift, stale intentional-layout references, and real regressions. Preserve strict useful checks; no blanket tolerance or blind baseline promotion.
2. Reproduce functional failures using suite-qualified selectors. Trace lifecycle cancellation, activity cleanup, reconciliation fencing, provider transitions, and context read timing. Fix root causes with focused regression evidence; no arbitrary timeout increases.
3. Use Composer 2.5 Fast for disjoint implementation work, Grok 4.6 Extra High Fast for scoped validation, and main session for visual evidence and coordination. Workers share this worktree and must preserve one another's files. Serialize xcodebuild jobs against shared DerivedData.
4. Inspect rendered comparisons, review changed code, run full suite, and build Release. Recheck native flows for any affected product behavior. Update evidence and existing PR. Keep main checkout and unrelated local edits untouched.
5. Merge only after local build/tests and CI pass under the user's existing authorization. No scope expansion beyond these failures.
