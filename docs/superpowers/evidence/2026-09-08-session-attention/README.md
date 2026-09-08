# Session attention acceptance status

Status: BLOCKED at native acceptance. Parent reviewed production through `e8f1294` and approved the final Working, Needs your response, and quiet Ready snapshots. The 31 focused attention/navigation, router, unread, viewport, and snapshot checks are recorded in `.superpowers/sdd/session-attention/report.md` in the implementation workspace.

The arm64 Release build passed and was packaged as `/tmp/10x-signals-final-build/10x-signals.app`, bundle ID `com.nextstep.tenx.signalsqa`. Its executable and build-log hashes are recorded in `manifest.json`. This package has not been launched because the Mac is locked. A compiled app and approved snapshots are not native focus/scroll evidence.

The included `attention-control.py` preserves the controlled RPC fixture for this task's isolated `/tmp/10x-session-recovery-home`. It seeds neutral transcript history and emits confirm, select, and input requests after 12, 14, and 16 seconds. It records the responses for explicit checking. The isolated wrapper routes only `projects/attention` to its installed fixture copy. No user provider policy is changed. Existing Stop acceptance against this fixture is separately recorded in PR #36; it does not establish the arrival-focus behavior introduced here.

Remaining native checks: compare rail/header/composer states across two sessions; type while reading older content as requests arrive; verify focus and position remain; activate header and composer jumps separately; resolve multiple requests in order; inspect Return, Tab, cancellation/timeout, and unread-completion behavior. Integrate PR #36's durable Stop correction before claiming the combined request-and-Stop flow.

Final integration must retain PR #35's later controller-owned disclosure and passive visible scroll targets. Keep this PR draft until native and integration gates are satisfied. No merge or deployment.
