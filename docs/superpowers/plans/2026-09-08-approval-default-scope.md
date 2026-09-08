# Clarify approval default scope

The authorized PERMISSIONS audit item needs an honest explanation of the policy the application can observe. OMP 18.1.10's `rpc-ui` transport supplies one-call Approve/Deny choices; it does not report an active session's effective approval policy or support an Always Allow response. The current settings service runs global `omp config` commands without a project cwd. Project configuration and per-tool policy can override those defaults in newly launched runtimes.

## Bounded change

Label the OMP settings metadata as global defaults while retaining the actual configuration path and setting count. For `tools.approvalMode` and `tools.approval`, add concise scope text: "Applies to new OMP sessions. Project configuration and per-tool policies can override this default." Keep the runtime-provided setting description and options authoritative. Do not add a mode selector to a session, relabel active sessions, change any policy, or introduce Always Allow.

## Ownership and checks

- Worktree `/tmp/10x-audit-permissions`, branch `codex/active-session-permission-scope`, based on current main `0be4353` so the merged OMP settings editors are retained.
- Worker owns `App/Settings/SettingsView.swift`, `SettingRowView.swift`, and one targeted settings snapshot fixture in `Tests/TenXAppTests/ViewSnapshotTests.swift`. A small definition computed property is allowed only if it prevents duplicated key checks; no new settings model or protocol abstraction.
- Read writing-ui and visual-ui. This is a low-impact copy change: use the existing metadata/description style, one focused light/dark snapshot pair, and existing targeted setting-save checks. Do not add tests that merely mirror the literal copy.
- Parent must view and approve any candidate images before reference promotion. Use isolated `/tmp/10x-derived-permissions`. No full suite, dependency change, global/user config write, native UI, push, merge, or nested agents. You are not alone; do not edit another worktree.

## Task 1: Implement the scope explanation

- [ ] Add the global label and approval-specific scope copy, preserving runtime descriptions and controls.
- [ ] Produce a focused Safety settings snapshot with an approval mode and per-tool deny entry. Verify readability and that both default scope and overrides are explained. Report candidates, commands/counts, and any mismatch; commit after parent approval.

## Task 2: Parent acceptance and broader permission audit

- [ ] Build and inspect the Safety page in an isolated Release profile. Verify the global path/default explanation and the absence of an invented active-session policy or Always Allow control.
- [ ] Exercise existing confirm/select/input/cancel/timeout/multiple-request behavior, typing focus, Return, and Stop through the controlled attention fixture and the SIGNALS/STOP branches. Record each as native, regression-only, or unavailable with a reason; this copy PR does not reimplement those cards.
- [ ] If a settings save is exercised, use only the isolated QA profile and restore its own original value. Never change Tanner's actual policy. Document the transport limitation and outstanding stack verification in the audit roadmap/PR.

## Evidence basis

Installed OMP source `src/tools/approval.ts` resolves mode, per-tool, and call policy; `src/extensibility/extensions/wrapper.ts` implements the one-call RPC UI choices. The ACP transport's Allow always behavior is different and is not a capability of this app's RPC UI. `get_state` does not expose the effective policy of a running session, so the UI must describe the scope it actually controls.
