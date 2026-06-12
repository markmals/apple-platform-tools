---
id: error.uitool.windows-timeout
kind: error
depends-on: [domain.uitool.ipc, command.uitool.windows]
---

# Window enumeration timed out

## When this happens

The injected server must read the window list on the target's main thread, but the main thread did not service the marshaled request within the bounded timeout (per [[domain.uitool.ipc]]) — typically because the target is busy, beachballing, or paused in a debugger.

## What the user sees

A one-line structured JSON error on stderr with a recovery hint, an empty stdout, and exit code **7** (socket / main-thread timeout) per [[domain.uitool.ipc]]. The error object carries the canonical `TIMEOUT` code:

> `{"ok":false,"error":{"code":"TIMEOUT","message":"target main thread did not respond","recover":"ensure <app> is not blocked or paused, then retry"}}`

## What the user can do

- **Retry** — the timeout is bounded and non-destructive; the server returns the error rather than hanging, so a later request can succeed once the main thread is free.
- **Unblock the target** — bring the app to a responsive state (resume it if paused under a debugger, wait out a long operation), then re-run.

## Underlying cause (informational)

- The main-thread hop that snapshots `NSApp.windows` exceeded the bounded timeout; the server returns `TIMEOUT` rather than block the accept loop.

## Related

- [[command.uitool.windows]] — the verb that surfaces this.
- [[domain.uitool.ipc]] — threading model and exit-code mapping (exit 7).
