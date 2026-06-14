---
id: error.uitool.attach-timeout
kind: error
depends-on: [domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Socket or handshake timed out

## When this happens

The injected channel opened, but the schema handshake (`ping`) over the socket did not complete within its bounded timeout — typically because the target's main thread is busy (a blocking run loop or the spinning wait cursor) when the handshake marshals work to it.

## What the user sees

Exit code 7 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"TIMEOUT","message":"target main thread did not answer the handshake within the timeout","recover":"dismiss any modal in the target and re-attach"}}`

The wire `error.code` is the canonical `TIMEOUT` (exit 7). Both timeout shapes at attach or launch map to this one code: the main-thread hop exceeding its bounded window (the handshake reached the main thread but it did not answer), and the socket-level case where the handshake never returned at all. They are not split into separate codes — `TIMEOUT` covers the attach/launch-time bounded-wait family, the same way query-time main-thread hops report `TIMEOUT` ([[domain.uitool.ipc]]).

## What the user can do

- Dismiss any modal sheet or alert in the target that is blocking its main thread, then re-attach.
- Re-attach once the target is idle.

## Underlying cause (informational)

- The main-thread hop for the handshake exceeded its bounded timeout (≈500 ms) and returned `TIMEOUT` rather than hanging ([[domain.uitool.ipc]] threading).

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[domain.uitool.ipc]] — threading and the bounded main-thread timeout.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.handshake-timeout; [[story.uitool.launch]] — scenario.uitool.launch.handshake-timeout.
