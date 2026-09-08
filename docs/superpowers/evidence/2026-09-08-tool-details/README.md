# Tool details acceptance status

Status: BLOCKED at native acceptance. Production was reviewed through `34b5a44` and the arm64 Release build passed. Focused timing, output-tail, editor-routing, child-session, and snapshot results are recorded in the committed `.superpowers/sdd/tool-details/report.md`.

The isolated package is `/tmp/10x-details-final-build/10x-details.app`, bundle ID `com.nextstep.tenx.detailsqa`. Its executable hash and source commit are in `manifest.json`. It has not been launched. The Mac is locked; this is not native interaction evidence.

The included `details-control.py` is a controlled RPC fixture for this task's isolated `/tmp/10x-session-recovery-home`, not application code or a real provider run. A bounded subprocess check verified 45 cumulative output updates over about 20 seconds, one exact persisted tool-start marker, two completed tool results, and two child messages via both cold `-r` and warm switching. Parent reviewed the fixture and its cold-resume correction. `fixture-verification.json` records the observed counts.

Only the owned `projects/details` directory is routed to this fixture by the isolated OMP wrapper, forwarding its arguments. No user profile or project is routed to it. The successful pipe run left completed parent and child transcripts in the fixture bucket. Before a fresh streaming walkthrough, preserve that completed parent as pipe evidence and reset only the fixture parent to its header; keep the nested child transcript. The fixture accepts one prompt per empty parent. A completed parent is useful for child-link acceptance.

Remaining native checks: observe an advancing running timer and newest output; use Show more and Copy; open both paths of a multi-file diff in the preferred editor; inspect recent subagent arguments and open the reported child session. Use an owned disposable project for file/editor checks. The sending-while-scrolled acceptance is already recorded in PR #35 and must survive final integration.

Keep PR #41 draft for these checks and integration with the final passive-scroll correction. No merge or deployment.
