# Active session audit completion plan

## Goal and scope

Finish the comparison of 10x's active chat experience with T3 Code, with
visual evidence and a ranked basis for future implementation. This branch
contains audit documents and reproduction evidence only. Application changes
are outside its scope.

The 10x baseline is `59a4ae8faaea049bfc2ff540a4f021b3859080b6`.
The reference runtime is `t3@0.0.39`; reference source was read at
`569a8cd2c3303f55fd869687eb31359b5658cc78`. Source availability does not prove
a feature worked in the captured runtime.

## Work

1. Recover the existing seven dimension reports and completed challenge reviews.
   Preserve the supplied evidence byte for byte; keep conversation and private
   diagnostic journals outside git.
2. Reconcile duplicate findings and unsupported claims. Prioritize actual loss
   of work, interruption/recovery, transcript readability, and review of changes.
3. Verify image provenance. Label historical app captures, test-suite reference
   renders, current captures, runtime probes, and code-only conclusions separately.
4. Complete the missing persistence checks with isolated temporary fixtures and
   no model calls. Record actual results, including contradictions of prior analysis.
5. Produce a local HTML report plus a readable Markdown companion, a complete
   finding disposition index, and an evidence manifest. Give recommendations
   acceptance criteria without implementing them.
6. Inspect the rendered report once and make one correction pass if needed.
   Check file/reference integrity, then commit the local audit deliverable.

## Report treatment

- Audience: the person deciding the next 10x implementation slices.
- Job: distinguish failures to fix, interaction improvements to prioritize, and
  capabilities that require a product decision.
- Palette: the existing 10x white `#FFFFFF`, ink `#0C0C0B`, cyan `#00A7C4`,
  signal red `#FF3B24`, and yellow `#FFC400`. Accessible darker variants serve
  small text; dark mode uses coordinated tokens.
- Type: restrained Outfit headings, native system body text, system monospace
  for source references and evidence labels, with explicit fallbacks.
- Layout: a concise thesis and paired app captures, followed by ranked findings,
  a comparison table, targeted visual comparisons, and a source/evidence appendix.
  Content sets heights. Wide material scrolls within its own container.

## Completion criteria

- Every original dimension is represented; every recovered finding is retained,
  merged, qualified, or rejected with a stated disposition.
- No stub copy, false claim of fresh UI verification, invented approval capture,
  or completed-workflow claim remains.
- The current report can be opened and read locally; screenshots are embedded.
- The final handoff identifies the local branch and commit, verification limits,
  and the next concrete implementation decision.
- Public publishing, merge, release, and cleanup of recovered sessions remain
  outside this continuation. The report is the local review surface.
