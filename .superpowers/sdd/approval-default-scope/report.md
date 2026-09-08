# Approval default scope — Task 1 report

Status: DONE

## Implemented

- Labels the displayed OMP configuration as `Global OMP defaults` while retaining the resolved path and setting count.
- Explains that `tools.approvalMode` and `tools.approval` apply to new OMP sessions and can be overridden by project configuration; approval mode also calls out per-tool policies.
- Adds focused light and dark settings snapshots covering `always-ask` and a per-tool `bash: deny` policy.

## Verified

- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug -derivedDataPath /Users/tannerpham/Library/Developer/Xcode/DerivedData/10x-aeaprfrgcfzmarhgxipsdmykgcoj build-for-testing CODE_SIGNING_ALLOWED=NO` passed. Log: `/tmp/10x-permissions-corrected-build-for-testing.log`.
- Parent visually approved both 1060×720-point candidates for readability, hierarchy, contrast, and clipping. The promoted files are byte-identical to those candidates:
  - Light: `7434b9d0141bf345a832256e4f96c7660d5a6fc5a4d0fc031454cb5fff429e9a`
  - Dark: `7ac3c787e1e394eeb9583d55e3a6755e9c4dfb3b010be037772058545fbda9f2`
- From code/reference commit `cb62ede403c0d9dfd972b5c82e91990d91e3acb0`, one incremental `xcodebuild test` invocation copied the promoted resources and passed all four selected tests: `approvalDefaultScopeSnapshot()`, `approvalDefaultScopeDarkSnapshot()`, `configServiceUsesTheExactOMPCommands()`, and `rapidSavesOnSameKeyApplyInIssueOrder()`. Log: `/tmp/10x-permissions-final-resource-rebuild.log`.
- `git diff --check` passed before promotion.

## Not verified

- An arm64 Release build was not run in this task; the parent owns that sequential verification step and the shared build cache.
