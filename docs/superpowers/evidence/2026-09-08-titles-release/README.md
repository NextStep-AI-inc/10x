# Session titles and metadata acceptance

Status: native feature acceptance passed in the arm64 Release build. PR #44 remains draft for stack integration.

## Verified

- Generated naming: the real OMP 18.1.10 / Cursor Grok 4.6 Fast turn persisted “Check title and branch metadata”. The disposable repository moved from `qa-branch-a` to `qa-branch-b` through its actual tool, and the header refreshed while the session remained open.
- Retained-session refresh: an external branch change in that disposable repository to `qa-branch-c` appeared after switching away and back. Its HEAD stayed `136c32b2b3d78c8811c164597744e9f4835bfdb2`, with no file changes.
- Two separate sessions accepted the same manual title, “Metadata duplicate”, and still reopened their distinct histories.
- Normal quit/relaunch reopened the saved session route. When the disposable saved project was temporarily moved aside, startup skipped that route and opened a new prompt in an available project. Another existing session opened normally. The project was then restored, with HEAD and clean status verified.
- A unique neutral QA title-generation request was made to return an invalid title. The accepted real prompt persisted and displayed its first-80-character fallback in both header and rail. The narrowly scoped QA wrapper probe was removed afterward. See `native-fallback-verification.json`.
- Existing six naming and three metadata/navigation checks passed; the signed build and exact source/executable hashes remain in `manifest.json`.

## Evidence and limits

Primary native images include `native-tool-branch-b.jpg`, `native-return-branch-c.jpg`, `native-duplicate-titles.jpg`, `native-relaunch-route.jpg`, `native-fallback-title.jpg`, and `native-missing-project-recovered.jpg`. Accessibility captures omit provider-account rows. During missing-project recovery the next available project was the deliberate model-failure fixture, so its expected model warning is visible in the initial fallback screen; this did not prevent opening another existing session.

This feature build uses an older draft-recovery base. Integration must retain PR #42's later durable send barrier and Continue-after-preload correction, as well as the later Review, Stop, and scroll changes. Native verification used only disposable repositories. No user checkout, merge, or deployment changed. The QA app was closed after acceptance.
