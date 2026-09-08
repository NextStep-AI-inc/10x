# Approval default scope — Task 1 report

Status: DONE_WITH_CONCERNS

## Implemented

- Labels the displayed OMP configuration as `Global OMP defaults` while retaining the resolved path and setting count.
- Explains that `tools.approvalMode` and `tools.approval` apply to new OMP sessions and can be overridden by project configuration; approval mode also calls out per-tool policies.
- Adds focused light and dark settings snapshots covering `always-ask` and a per-tool `bash: deny` policy.

## Verified

- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug -derivedDataPath /Users/tannerpham/Library/Developer/Xcode/DerivedData/10x-aeaprfrgcfzmarhgxipsdmykgcoj build-for-testing CODE_SIGNING_ALLOWED=NO` passed. Log: `/tmp/10x-permissions-corrected-build-for-testing.log`.
- Parent visually approved both 1060×720-point candidates for readability, hierarchy, contrast, and clipping. The promoted files are byte-identical to those candidates:
  - Light: `7434b9d0141bf345a832256e4f96c7660d5a6fc5a4d0fc031454cb5fff429e9a`
  - Dark: `7ac3c787e1e394eeb9583d55e3a6755e9c4dfb3b010be037772058545fbda9f2`
- A final `test-without-building` invocation selected four tests. `configServiceUsesTheExactOMPCommands()` and `rapidSavesOnSameKeyApplyInIssueOrder()` passed. Both newly rendered snapshot `.actual.png` files matched the approved references byte-for-byte at the hashes above. Log: `/tmp/10x-permissions-final-focused.log`.
- `git diff --check` passed before promotion.

## Not verified

- The final snapshot harness pass was not obtained. Because `test-without-building` reused a test bundle created before reference promotion, the bundle contained neither new reference image. The run therefore exited 65 with exactly two missing-reference issues despite the source-tree `.actual.png` files matching their references byte-for-byte. A resource rebuild is required before rerunning these snapshots; this is not a passing test result.
- The earlier candidate invocation also produced its expected two missing-reference issues, then exited 133 while writing diagnostics because the disk was full. Log: `/tmp/10x-permissions-corrected-snapshot-candidates.log`.
- The requested arm64 Release build remains paused until disk space is recovered.
