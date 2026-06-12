---
id: error.uitool.find-not-attached
kind: error
depends-on: [domain.uitool.ipc, command.uitool.find, domain.uitool.injection]
status: draft
---

# Target not attached

## When this happens

The agent runs `find` against an app that uitool has not injected into (or whose injection has gone away). There is no server-side tree to evaluate the selector against. This is distinct from the app not being running at all (exit 3).

## What the user sees

A one-line structured JSON error object on stderr, and exit code **4** per [[domain.uitool.ipc]].

> `{"error":{"code":"NOT_ATTACHED","message":"no uitool session for com.apple.mail","recover":"run: uitool attach com.apple.mail"}}`

The wire `error.code` is the canonical string **`NOT_ATTACHED`**, per [[domain.uitool.ipc]]'s error-code vocabulary.

## What the user can do

- Attach first (`uitool attach <app>`) and re-run the same `find`.
- If attach itself fails, run `uitool doctor` to check the SIP/AMFI/LV/arch preconditions ([[domain.uitool.injection]]) — a precondition failure surfaces separately as exit 6. `doctor` detects and instructs by default; to opt into auto-remediation of the fixable preconditions, run `uitool doctor --fix` (it echoes each command before running it and prints the manual steps + reboot it cannot perform — per [[domain.uitool.injection]]).

## Underlying cause (informational)

- No socket exists at `/tmp/uitool-<pid>.sock` for the resolved target.
- The dylib was injected but has since unloaded (app quit, detached, or registry dropped).

## Related

- [[command.uitool.find]] — issues exit 4 for this.
- [[domain.uitool.ipc]] — transport and the exit-code mapping.
