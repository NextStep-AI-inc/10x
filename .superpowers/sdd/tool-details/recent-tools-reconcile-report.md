# Recent child-tool reconciliation

Status: implementation, focused checks, and final native Release acceptance verified.

The native controlled child card lost its recent tools and output when completed task history replaced live progress. The fixture uses the same subagent-progress envelope as installed OMP 18.1.10. Persisted task results contain final status and output, but omit the recent progress details.

`TranscriptReducer.reconcile` now fills only missing recent-tool and recent-output arrays from the same live child identity. Persisted completion, result, and model fields remain authoritative. Cold history still shows only recorded data.

- Regression `persistedSubagentCompletionKeepsLiveRecentDetails` failed with both recent arrays empty before the fix: `/tmp/10x-details-recent-reconcile-red.log`.
- That regression passed after the fix: `/tmp/10x-details-recent-reconcile-green.log`.
- Seven focused reconciliation and identity checks passed: `/tmp/10x-details-recent-reconcile-focused.log`.
- The separately accepted multi-file extractor reuse passed 48 extractor, diff, resolver, and preferred-editor checks before this correction.

The parent completed implementation after the assigned workers reached their usage limit. No merge, deployment, or user-profile change occurred. Native evidence and the final package hash will be recorded with acceptance.

Final native run retained all three recent tools and latest progress output after completion. Source `36e16de`; signed executable `5159405488da8821cc2435c9dbd9d5a4acd9a53065c60fdd46c5620ad3ffc271`. Evidence: `docs/superpowers/evidence/2026-09-08-tool-details/README.md`.
