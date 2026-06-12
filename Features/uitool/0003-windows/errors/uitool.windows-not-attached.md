---
id: error.uitool.windows-not-attached
kind: error
depends-on: [domain.uitool.ipc, domain.uitool.injection, command.uitool.windows]
---

# Windows requested before attach

## When this happens

The agent runs the windows verb against an app it has not attached to (no injected server / no socket for that target), so there is no live object graph to enumerate.

## What the user sees

A one-line structured JSON error on stderr with a recovery hint, an empty stdout, and exit code **4** (not attached / injection failed) per [[domain.uitool.ipc]]. The error object carries the [[domain.uitool.ipc]] message-shape fields — the int protocol version `v`, the echoed request `id`, the semver `schemaVersion`, `ok: false`, and the `error` payload with the canonical `NOT_ATTACHED` code:

> `{"v":1,"id":1,"schemaVersion":"1.0.0","ok":false,"error":{"code":"NOT_ATTACHED","message":"no uitool session for <app>","recover":"run 'uitool attach <app>' first"}}`

## What the user can do

- **Attach first** — run `uitool attach <app>`, then re-run `uitool windows <app>`.
- **Check the target is running** — if the app is not running, attach itself fails with exit 3; resolve that first.

## Underlying cause (informational)

- See [[domain.uitool.ipc]] and [[domain.uitool.injection]] for the conditions that produce this state: no listening server for the resolved target, whether because no socket exists or because injection failed at attach time.

## Related

- [[command.uitool.windows]] — the verb that surfaces this.
- [[domain.uitool.ipc]] — exit-code mapping (exit 4).
