---
id: error.uitool.attach-not-running
kind: error
depends-on: [domain.uitool.ipc, command.uitool.attach]
---

# Target app is not running

## When this happens

The agent attaches to a target whose process does not exist — a wrong pid, or a bundle id for an app that is not currently launched.

## What the user sees

Exit code 3 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"APP_NOT_RUNNING","message":"no process for com.example.SampleAppKit","recover":"launch the app, or pass a live pid (see uitool list-apps)"}}`

The wire `error.code` for the not-running case is `APP_NOT_RUNNING` (exit 3) — canonical.

## What the user can do

- Launch the target app, then re-attach.
- List attachable processes (`uitool list-apps`) to confirm the pid / bundle id.

## Underlying cause (informational)

- The requested pid does not exist, or the bundle id resolves to no running process.

## Related

- [[command.uitool.attach]] — the verb that surfaces this.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.not-running.
