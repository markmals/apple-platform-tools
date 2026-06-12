---
id: error.uitool.find-timeout
kind: error
depends-on: [domain.uitool.ipc, domain.uitool.selector, command.uitool.find]
---

# Search timed out on the target's main thread

## When this happens

The selector / predicate parses and runs, but the server-side evaluation cannot complete within the bounded main-thread window (≈500 ms per [[domain.uitool.ipc]]) — typically because the target's main thread is busy or the tree is very large. uitool returns rather than hang the host: evaluation is bounded by design, so this surfaces as a timeout, never a frozen target.

## What the user sees

A one-line structured JSON error object on stderr, and exit code **7** per [[domain.uitool.ipc]].

> `{"error":{"code":"TIMEOUT","message":"target main thread did not respond within the budget","recover":"narrow the selector or retry once the target is idle"}}`

The wire `error.code` is the canonical string **`TIMEOUT`**, per [[domain.uitool.ipc]]'s error-code vocabulary (covering both the bounded main-thread hop and the socket round-trip).

## What the user can do

- Narrow the query (a tighter `--class` selector or more `--where` constraints) so server-side evaluation visits fewer nodes, then re-run.
- Retry once the target app is idle (e.g. not mid-animation or mid-load).
- Use `--count-only` first to size a narrower selector before pulling records.

## Underlying cause (informational)

- The per-request main-thread hop exceeded its bounded budget; the server returned `TIMEOUT` instead of blocking.
- The socket round-trip exceeded its timeout.

## Related

- [[command.uitool.find]] — issues exit 7 for this.
- [[domain.uitool.ipc]] — the threading model and ≈500 ms main-thread budget.
- [[domain.uitool.selector]] — evaluation is total and bounded, which is why this is a timeout, not a hang.
