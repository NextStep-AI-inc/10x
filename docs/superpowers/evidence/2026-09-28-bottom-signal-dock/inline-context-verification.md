# Session-only inline context verification

Product commit: `b291733d80a00ad9f33842a3760937c08fb73ed5` on `codex/bottom-dock-design`.
Release executable SHA256: `8d2dd368f77abc3f7e14bfaa05351bee6a263678cc939fc0ed290b9c21917364`.

## Verified

- Release build succeeded. Five focused snapshot checks passed; see `inline-context-tests.log`. Active references were inspected and updated; new-session references passed unchanged.
- Native Release session shows a short leading segment, Context 42%, and resumed line. Text has no distinct resting badge; attachment/model/status retain their layout. See `inline-context-session.jpg` and its detail crop.
- Clicking the inline label opens existing context details (84,000 / 200,000 tokens); Escape closes it. See `inline-context-details.jpg`.
- Cmd-N removes the label and break, leaving a continuous line. See `inline-context-new-session.jpg` and its detail crop.
- Archived screen also shows a continuous line with no context label. See `inline-context-archived.jpg`.
- Isolated QA process 52499 exited after Cmd-Q. Disposable fixture profile; no real provider requests.

## Not verified

Native narrow-window interaction and hover-only transition were not repeated. Narrow rendering passed its focused snapshot check. The broader suite was not rerun for this layout correction; prior full-suite failures remain documented in README. PR remains draft.

## For Tanner to test

Visual feel of the inline label and its spacing in regular use.
