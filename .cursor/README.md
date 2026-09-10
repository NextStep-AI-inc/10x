# Cloud Agent environment (Linux)

`10x` is a macOS SwiftUI app. Its app target, the `TenXAppTests` Xcode bundle,
and `OmpKit` (which imports `Darwin`) build **only on macOS with Xcode 26.x** and
cannot be built or run on a Linux Cloud Agent — the release pipeline runs on a
`macos-15` runner for that reason (`.github/workflows/release.yml`).

This environment sets up the parts of the repo that *do* run on Linux, via
[`install.sh`](./install.sh):

| Component | Toolchain | Command |
| --- | --- | --- |
| Xcode project generator | Ruby + `xcodeproj` 1.27.0 | `ruby scripts/generate_xcodeproj.rb` |
| `OmpExtension` test suite | Bun + `omp` (`@oh-my-pi/pi-coding-agent`) | `cd OmpExtension && bun test` |

## Regenerating `10x.xcodeproj`

```bash
ruby scripts/generate_xcodeproj.rb
```

Generation is byte-reproducible, so a clean tree yields an empty `git diff`.
See `AGENTS.md` for the rules around the generated project file.

## Running the OmpExtension tests

```bash
cd OmpExtension
bun test
```

34 of the 35 tests are pure unit tests. The one integration test in
`test/command-channel.test.ts` spawns the real `omp` runtime, which refuses to
boot without a model configured. It never calls a model (it only exercises the
RPC command channel), so **any** API-key environment variable is enough to let
`omp` start:

```bash
OPENAI_API_KEY=sk-not-a-real-key bun test
```
