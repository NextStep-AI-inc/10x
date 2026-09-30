# Resting fill removed, 2026-09-29

Product `f73ba4eb63efc1239455a194ff7ef281f78ebefc` removes only the two added resting-background modifiers, as requested. Outer/internal padding and original GhostActionStyle hover remain.

Verified: four focused tests passed (`context-no-fill-tests.log`), five affected renders inspected, and isolated universal Release succeeded (`/tmp/10x-context-no-fill-final-release.log`). Executable SHA-256 `20f5315de89b08831f9934d570e79ab2d63bf20d519285e6c1234b6cbf71b3dc`. Native Release PID 44075 showed the transparent label, click opened details, Escape closed them. QA app quit and PID was absent. Evidence: `context-no-fill-native.jpg`; `context-no-fill-detail.png` is an unaltered-layout crop. No real provider calls.

Not verified: no broad suite, native narrow interaction, dark appearance, or dedicated hover-only pass repeated for this two-line reversal. For Tanner: confirm the transparent resting appearance feels right.

The earlier filled treatment below is superseded.

---

# Context control refinement, 2026-09-29

Product `c88c228d3c03fa34f8839b2405b8b32cc68feb1a` adds an 8-point outer inset, 6-point internal horizontal padding, and an adaptive neutral resting fill at 0.55 opacity. Text stays 10 points. The existing GhostActionStyle hover behavior is unchanged; its full hover background draws over the resting fill. There is no new border, icon, shadow, or custom interaction state.

## Verified

- Four focused rendering tests passed; five affected references inspected. Output/command: `context-chip-focused-tests.log`.
- Universal isolated Release succeeded: `/tmp/10x-context-chip-final-release.log`. Bundle `com.nextstep.tenx.bottomdockqa`; binary SHA-256 `d9e744e9370d723f7b0205138a85c89e71a7a802c724a30fa80d95dac2129d19`.
- Native Release PID 35210, disposable local fixture profile `/tmp/10x-placement-qa/profile`: resting background/padding inspected; clicking the context control opens its details and Escape closes it. Draft typing remains functional.
- `context-chip-native.jpg` and `context-chip-open.jpg` are native captures; `context-chip-detail.png` is a crop focused on the changed control and nearby editor controls, without layout alteration. The capture surface omitted the far-right portion of this window, so this pass makes no native full-width-layout claim.
- QA app quit and PID was absent afterward.

## Limits

The original hover code is retained and reviewed. A screenshot after clicking and dismissing showed the pointer over the control, but the automation exposes no dedicated hover action; exact hover-only color transitions were not conclusively verified natively. Native narrow interactions and dark appearance were not repeated for this small refinement; focused wide/narrow rendering checks passed. No full-suite rerun; earlier broader suite failures remain unresolved.

## For Tanner to test

Confirm the resting fill feels subtle enough and the familiar hover appearance feels right with a physical pointer.
