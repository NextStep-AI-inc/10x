# Session attention acceptance status

Status: **DONE_WITH_CONCERNS** for native acceptance. Parent accepted the SIGNALS behavior in the signed arm64 Release app at `/tmp/10x-signals-final-build/10x-signals.app`, bundle ID `com.nextstep.tenx.signalsqa`. The executable remained `9fd40a85225c7a1d32aa3981492d98695492443ea9f35d94521d624c82f62813`. The app was quit with Command-Q after the final capture. This is not an integrated build, a ready-for-merge claim, or a deployment.

## Verified natively

- `before-request-arrival.jpg` and `after-request-arrival.jpg` retain the same older-history position while the controlled requests arrive. The staged draft changed from `DRAFT-KEEPS-FOCUS` to `DRAFT-KEEPS-FOCUSx` after arrival, proving typing focus stayed in the composer.
- The header action revealed the earliest pending confirm (`header-reveals-first-request.jpg`). The composer action then revealed the next select (`composer-reveals-next-request.jpg`). `decisions-completed.jpg` captures the completed controlled turn.
- Pressing Return with an empty composer before any decision sent no extension response and created no extra prompt; `arrival-control.jsonl` retains that first-instance trace. On the fresh controlled turn, Run sent `confirmed: true`, Reviewed sent a value of length 8, Tab focused the input Cancel control without submitting, and clicking the input before pressing Return submitted 21 characters. `request-decisions-control.jsonl` contains exactly one matched response for each request.
- The first app instance exited normally but unexpectedly after the first Run response. A bounded OS diagnostic reported exit status 0 and no crash report; the cause remains unknown. Its arrival trace was retained, and the app was relaunched to complete a fresh controlled turn.
- `two-session-statuses.jpg` proves only the Working state. `two-session-pending.jpg` and `background-pending.jpg` show native session A Ready while background session B Needs your response. `background-completion.jpg` shows B Ready and unread while A remains active. Opening B cleared unread, captured by `completion-acknowledged.jpg`.
- In the edge fixture, the input Cancel response at `2026-09-08T17:31:14.286Z` contained `cancelled: true` without `timedOut`. The confirm response at `2026-09-08T17:31:57.713Z`, 60.2 seconds after arrival, contained both `cancelled: true` and `timedOut: true`; the turn ended at `17:31:57.715Z`. `edge-control.jsonl` is the authoritative trace.

## Evidence and limits

`manifest.json` hashes every captured JPG, control trace, fixture, and evidence document, plus the unchanged Release executable and build log. `native-observations.json` records the acceptance facts in machine-readable form.

The initial fixture precondition rejection remains a fixture limitation and is not evidence of a production defect. The cause of the first app instance's clean exit is unresolved. The final stack must retain PR #36's durable Stop behavior and PR #35's later controller-owned disclosure and passive visible scroll targets. Those integrations were not present in this signed Release and still require their own combined build and acceptance. No merge or deployment occurred.
