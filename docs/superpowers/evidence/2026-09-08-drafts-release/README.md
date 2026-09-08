# Composer draft and route recovery acceptance

Status: native feature acceptance passed in the rebuilt arm64 Release app. PR #42 remains draft for stack integration.

## Verified

- The final source is `d6e1508f82c9936115af8fe918530973cdd910ed`. Package identity, executable hash, and build/check logs are in `route-fix-package.json`; the earlier package remains historical in `manifest.json`.
- A session draft containing text and a 600×220 PNG, a separate session text draft, and a new-project prompt survived switching, normal quit, and relaunch. The saved existing-session route reopened automatically, with its text and image visible.
- The controlled runtime received exactly one 66-character prompt with one image, then withheld acknowledgment and echo. After normal quit/relaunch, the draft and identical image bytes returned with “A previous send wasn’t confirmed” guidance. No automatic replay occurred; the transcript still contained only its session header. See `native-unconfirmed-verification.json` and the captured control log.
- Fourteen final store/send-boundary checks had passed for serialized writes, failed writes, delayed flushes, newer content, and invalidated pipelines. The native startup check exposed a separate Continue-to-workspace route gap. The three-line correction calls the existing guarded route restoration after the cancelled startup task has joined; its regression plus three adjacent Continue guards passed.
- Current primary native images: `native-last-route-restored.jpg`, `native-session-b-restored.jpg`, `native-new-project-restored.jpg`, and `native-unconfirmed-restored.jpg`. Accessibility captures omit provider-account rows. The parent inspected the restored-route and unconfirmed screenshots.

## Limits

The final relaunch used the normal prepared-workspace path. The timed-out optional-preload Continue path is covered by the new regression; pre-fix native timeout evidence is retained in `native-startup-warm-timeout.*`. No unconfirmed prompt was resent manually.

This is a feature build on the older Review base. Final integration must retain durable send ordering and include later Review, Stop, and scroll fixes. No full suite was repeated; known baseline activity snapshots remain recorded. No merge or deployment occurred. The QA app was closed after acceptance.
