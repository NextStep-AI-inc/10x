# Auto-Update Relaunch Fix Design

## Problem

Sparkle already sends the application a quit event before it calls
`showInstallingUpdate(withApplicationTerminated:retryTerminatingApplication:)`.
`SplashUpdateDriver` sends a second `NSApplication.terminate(_:)` from that callback.
When `AppTerminationDelegate` has returned `.terminateLater`, the second request blocks
the main actor inside AppKit. The delegate's asynchronous shutdown task cannot send its
termination reply, so Sparkle waits forever and never swaps or relaunches the app.

## Approved approach

Sparkle remains the sole owner of the termination request. The install callback only
moves `UpdateState` into `.relaunching`; it does not terminate the application or invoke
Sparkle's retry closure. The existing termination delegate continues to await runtime
shutdown and then replies to Sparkle's original quit event.

The intended flow is:

```text
Sparkle sends quit
  -> AppTerminationDelegate returns terminateLater
  -> shutdown task completes on the main actor
  -> delegate replies that termination may continue
  -> app exits
  -> Sparkle swaps the bundle and relaunches
```

## Scope

- Remove the duplicate termination dependency and call from `SplashUpdateDriver`.
- Replace the test that required the duplicate quit with coverage for Sparkle-owned
  termination and the relaunching state transition.
- Run focused and full tests, build Release, and repeat the real updater flow.
- Do not change update UI, Sparkle version, release version, or shutdown semantics.
